// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Security
import Testing

/// The label and service strings identify keychain items. Changing one orphans
/// every secret already on disk, so they are pinned here rather than left to the
/// enum's implementation.
@Suite("Keychain item naming")
struct KeychainItemTests {
	@Test(
		"Service names spell out the kind of secret",
		arguments: [
			(KeychainItem.nicknamePassword("abc"), "glasstual.nickserv.abc"),
			(KeychainItem.proxyPassword("abc"), "glasstual.proxy-server.abc"),
			(KeychainItem.serverPassword("abc"), "glasstual.server.abc"),
			(KeychainItem.channelSecretKey("abc"), "glasstual.channel-key.abc"),
		]
	)
	func serviceNames(item: KeychainItem, expected: String) {
		#expect(item.service == expected)
	}

	@Test(
		"Labels keep the text Keychain Access shows",
		arguments: [
			(KeychainItem.nicknamePassword("abc"), "Glasstual (NickServ)"),
			(KeychainItem.proxyPassword("abc"), "Glasstual (Proxy Server Password)"),
			(KeychainItem.serverPassword("abc"), "Glasstual (Server Password)"),
			(KeychainItem.channelSecretKey("abc"), "Glasstual (Channel JOIN Key)"),
		]
	)
	func labels(item: KeychainItem, expected: String) {
		#expect(item.label == expected)
	}

	/// The store names one access group on every call, so a read cannot answer
	/// with an item the application left in its other entitled group. The group
	/// it names is the first of the application's entitlement, which project.yml
	/// spells `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER).secrets`.
	@Test("A written secret lands in the application's secrets access group")
	func writesGoToTheSecretsAccessGroup() throws {
		let item = KeychainItem.serverPassword(UUID().uuidString)
		#expect(item.write("stored-secret"))
		defer { item.delete() }

		/* No access group in this query: it asks where the item actually is,
		 across every group the process may reach. */
		var result: CFTypeRef?
		let status = SecItemCopyMatching(
			[
				kSecClass: kSecClassGenericPassword,
				kSecAttrService: item.storedService,
				kSecUseDataProtectionKeychain: true,
				kSecMatchLimit: kSecMatchLimitAll,
				kSecReturnAttributes: true,
			] as CFDictionary,
			&result
		)
		#expect(status == errSecSuccess)

		let attributes = try #require(result as? [[String: Any]])
		#expect(attributes.count == 1)
		let group = try #require(attributes.first?[kSecAttrAccessGroup as String] as? String)
		#expect(group.hasSuffix(".secrets"))
	}
}
