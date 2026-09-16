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
	/// data-protection keychain reported errSecItemNotFound.
	@Test("A missing item reads as absent rather than searching elsewhere")
	func missingItemReadsAsAbsent() {
		let item = uniqueItem()

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

		#expect(item.password == nil)
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
}
