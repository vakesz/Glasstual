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
import Testing

/// The label and service strings identify keychain items written by earlier
/// releases. Changing one orphans every secret already on disk, so they are
/// pinned here rather than left to the enum's implementation.
@Suite("Keychain item naming")
struct KeychainItemTests {
	@Test(
		"Service names keep the prefix earlier releases wrote",
		arguments: [
			(KeychainItem.nicknamePassword("abc"), "glasstual.nickserv.abc"),
			(KeychainItem.proxyPassword("abc"), "glasstual.proxy-server.abc"),
			(KeychainItem.serverPassword("abc"), "glasstual.server.abc"),
			(KeychainItem.channelSecretKey("abc"), "glasstual.cjoinkey.abc"),
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

	@Test("Every secret is stored as an application password")
	func itemClasses() {
		let items: [KeychainItem] = [
			.nicknamePassword("abc"),
			.proxyPassword("abc"),
			.serverPassword("abc"),
			.channelSecretKey("abc"),
		]

		for item in items {
			#expect(item.itemClass.descriptionAttribute == "application password")
		}
	}
}
