/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Security
import Testing

@Suite("Keychain store", .serialized)
@MainActor
struct KeychainStoreTests {
	private func uniqueItem() -> KeychainItem {
		.serverPassword(UUID().uuidString)
	}

	/// The tests run inside the application and share its access group, so
	/// every item they touch carries the prefix that keeps it apart from the
	/// user's real secrets.
	@Test("Items written by the tests are kept apart from real secrets")
	func itemsAreIsolated() {
		let item = uniqueItem()

		#expect(item.storedService == "glasstual.tests." + item.service)
	}

	@Test("A password written to the data-protection keychain reads back")
	func passwordRoundTrips() {
		let item = uniqueItem()
		defer { item.delete() }

		#expect(item.write("hunter2"))
		#expect(item.password == "hunter2")
	}

	/// The lookup used to fall through to the file keychain when the
	/// data-protection keychain reported errSecItemNotFound. It now reports
	/// that absence straight back to the caller, distinct from a refused read.
	@Test("A missing item reports that it is missing rather than searching elsewhere")
	func missingItemReportsNotFound() {
		let item = uniqueItem()

		#expect(item.readPassword() == .missing)
		#expect(item.password == nil)
	}

	/// deleteItem used to discard the result of a second, legacy delete; its
	/// return value now describes the one delete it performs.
	@Test("Deleting reports success once and failure afterwards")
	func deleteReportsTheDataProtectionResult() {
		let item = uniqueItem()
		// Nothing is left behind if an expectation below fails part-way.
		defer { item.delete() }

		#expect(item.write("hunter2"))
		#expect(item.delete())
		#expect(item.delete() == false)
	}

	/// `PendingKeychainSecret(_ value: String?)` treated a non-nil empty string
	/// as a secret to write, leaving an item holding nothing behind instead of
	/// removing the one the user had just emptied.
	@Test("An emptied field clears the item instead of storing an empty secret")
	func emptyEditClearsTheItem() {
		#expect(PendingKeychainSecret("") == .cleared)
		#expect(PendingKeychainSecret(nil) == .cleared)
		#expect(PendingKeychainSecret("hunter2") == .set("hunter2"))

		let item = uniqueItem()
		defer { item.delete() }

		#expect(item.write("hunter2"))
		item.apply(PendingKeychainSecret(""))

		#expect(item.readPassword() == .missing)
	}

	/// Lookups filtered on `kSecAttrLabel` and `kSecAttrDescription`, which are
	/// exactly the two attributes Keychain Access lets the user edit. Renaming
	/// an item there made the update miss, the add that followed collide, and
	/// the new password vanish without a word.
	@Test("A renamed item still takes a new password")
	func renamedItemStillTakesANewPassword() {
		let item = uniqueItem()
		defer { item.delete() }

		#expect(item.write("hunter2"))

		let identity: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: item.storedService,
			kSecUseDataProtectionKeychain: true,
		]
		let rename: [CFString: Any] = [
			kSecAttrLabel: "Renamed in Keychain Access",
			kSecAttrDescription: "note to self",
		]
		#expect(SecItemUpdate(identity as CFDictionary, rename as CFDictionary) == errSecSuccess)

		#expect(item.write("hunter3"))
		#expect(item.password == "hunter3")
		#expect(item.delete())
	}

	// MARK: - Access groups

	/// This process's `keychain-access-groups`: where secrets are written, then
	/// the group earlier builds wrote them to.
	private func accessGroups() throws -> (current: String, legacy: String) {
		let task = try #require(SecTaskCreateFromSelf(nil))
		let groups = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) as? [String]
		let declared = try #require(groups)
		try #require(declared.count == 2, "The application declares its secrets group and the legacy one")
		return (declared[0], declared[1])
	}

	private func accessGroups(holding item: KeychainItem) -> Set<String> {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: item.storedService,
			kSecUseDataProtectionKeychain: true,
			kSecMatchLimit: kSecMatchLimitAll,
			kSecReturnAttributes: true,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return [] }
		return Set((result as? [[CFString: Any]] ?? []).compactMap { $0[kSecAttrAccessGroup] as? String })
	}

	private func addLegacyCopy(of item: KeychainItem, password: String, in group: String) {
		let attributes: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: item.storedService,
			kSecAttrAccessGroup: group,
			kSecUseDataProtectionKeychain: true,
			kSecValueData: Data(password.utf8),
		]
		#expect(SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess)
	}

	/// Secrets used to land in the default group, which the IRC connection host
	/// was entitled to as well. They go to an application-only group now.
	@Test("A new secret is written to the application's own access group")
	func writesLandInTheSecretsGroup() throws {
		let groups = try accessGroups()
		let item = uniqueItem()
		defer { item.delete() }

		#expect(item.write("hunter2"))

		#expect(accessGroups(holding: item) == [groups.current])
	}

	@Test("A secret an earlier build stored in the legacy group is moved on first read, not lost")
	func legacySecretMigratesOnRead() throws {
		let groups = try accessGroups()
		let item = uniqueItem()
		defer { item.delete() }
		addLegacyCopy(of: item, password: "from-before", in: groups.legacy)

		#expect(item.readPassword() == .found("from-before"))

		#expect(accessGroups(holding: item) == [groups.current])
		#expect(item.password == "from-before")
	}

	@Test("Writing over a legacy secret leaves no copy behind in the legacy group")
	func writeRemovesTheLegacyCopy() throws {
		let groups = try accessGroups()
		let item = uniqueItem()
		defer { item.delete() }
		addLegacyCopy(of: item, password: "from-before", in: groups.legacy)

		#expect(item.write("replacement"))

		#expect(accessGroups(holding: item) == [groups.current])
		#expect(item.password == "replacement")
	}

	/// A delete that left the legacy copy would hand the secret straight back
	/// on the next read, through the migration.
	@Test("Deleting a secret removes it from every access group")
	func deleteReachesEveryGroup() throws {
		let groups = try accessGroups()
		let item = uniqueItem()
		defer { item.delete() }
		#expect(item.write("current"))
		addLegacyCopy(of: item, password: "from-before", in: groups.legacy)

		#expect(item.delete())

		#expect(accessGroups(holding: item).isEmpty)
		#expect(item.readPassword() == .missing)
	}
}
