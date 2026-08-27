/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class CompatibilityHeaderMigrationTests: XCTestCase {
	func testOptionalAndRequiredConfigurationValuesKeepTheirContracts() {
		let channel = ChannelConfig.seed(withName: "#swift")
		XCTAssertEqual(channel.channelName, "#swift")
		XCTAssertFalse(channel.uniqueIdentifier.isEmpty)
		XCTAssertNil(channel.label)
		XCTAssertNil(channel.defaultModes)
		XCTAssertNil(channel.defaultTopic)

		let clientConfig = ClientConfig(dictionary: ["dictionaryVersion": 710])
		XCTAssertFalse(clientConfig.connectionName.isEmpty)
		XCTAssertFalse(clientConfig.nickname.isEmpty)
		XCTAssertNotNil(clientConfig.channelList)
		XCTAssertNil(clientConfig.identityClientSideCertificate)
		XCTAssertEqual(clientConfig.awayNickname, "")
		XCTAssertNil(clientConfig.proxyAddress)

		let client = GLTTestClient()
		let connection = Connection(config: Glasstual.IRCConnectionConfig(), onClient: client)
		XCTAssertNotNil(connection.client)
		XCTAssertFalse(connection.uniqueIdentifier.isEmpty)
		XCTAssertNil(connection.connectedAddress)
	}

	func testNSStringHostmaskAccessorsPreserveParsedComponents() {
		let source: NSString = "nick!user@example.test"

		XCTAssertEqual(source.nicknameFromHostmask, "nick")
		XCTAssertEqual(source.usernameFromHostmask, "user")
		XCTAssertEqual(source.addressFromHostmask, "example.test")
		XCTAssertNil(("not a hostmask" as NSString).usernameFromHostmask)
	}

	func testSharedFormattingRemovesCompleteControlSequences() {
		let formatted = "\u{02}bold\u{02} \u{03}04,12palette \u{04}A1B2C3,001122hex\u{0F}"
		let expected = "bold palette hex"

		XCTAssertEqual(IRCFormatting.removingControlCodes(from: formatted), expected)
		XCTAssertEqual((formatted as NSString).stripIRCEffects, expected)
	}

	func testSharedFormattingPreservesMalformedColorSeparatorsAndUnicode() {
		XCTAssertEqual(IRCFormatting.removingControlCodes(from: "\u{03}04,text"), ",text")
		XCTAssertEqual(IRCFormatting.removingControlCodes(from: "\u{04}AABBCC,no"), ",no")
		XCTAssertEqual(IRCFormatting.removingControlCodes(from: "\u{03},plain 😀"), ",plain 😀")
	}

	func testSharedHostmaskParserPreservesValidationRules() throws {
		let hostmask = try XCTUnwrap(IRCHostmask(parsing: "nick!user@example.test"))

		XCTAssertEqual(hostmask.nickname, "nick")
		XCTAssertEqual(hostmask.username, "user")
		XCTAssertEqual(hostmask.address, "example.test")
		XCTAssertNil(IRCHostmask(parsing: "*!user@example.test"))
		XCTAssertNil(IRCHostmask(parsing: "nick!user name@example.test"))
		XCTAssertNil(IRCHostmask(parsing: "long-nickname!user@example.test", maximumNicknameLength: 4))
	}

	func testPluginHostResolvesContextualNicknameLengthThroughOpaqueClient() {
		let client = PluginHostClientFixture()
		client.supportInfo.maximumNicknameLength = 64

		XCTAssertEqual(PluginHost.maximumNicknameLength(on: client), 64)

		client.isConnectedToZNC = true
		XCTAssertEqual(PluginHost.maximumNicknameLength(on: client), 50)

		client.isConnectedToZNC = false
		client.supportInfo.configurationReceived = false
		XCTAssertEqual(PluginHost.maximumNicknameLength(on: client), 50)
	}
}

private final class PluginHostClientFixture: NSObject {
	@objc dynamic var isConnectedToZNC = false
	@objc dynamic let supportInfo = PluginHostSupportInfoFixture()
}

private final class PluginHostSupportInfoFixture: NSObject {
	@objc dynamic var configurationReceived = true
	@objc dynamic var maximumNicknameLength: UInt = 50
}
