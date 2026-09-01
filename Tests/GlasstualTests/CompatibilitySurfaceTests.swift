/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Objective-C compatibility surface")
struct CompatibilitySurfaceTests {
	@Test("Configuration values keep their optional and required contracts")
	func configurationValuesKeepTheirContracts() {
		let channel = ChannelConfig.seed(withName: "#swift")
		#expect(channel.channelName == "#swift")
		#expect(channel.uniqueIdentifier.isEmpty == false)
		#expect(channel.label == nil)
		#expect(channel.defaultModes == nil)
		#expect(channel.defaultTopic == nil)

		let clientConfig = ClientConfig()
		#expect(clientConfig.connectionName.isEmpty == false)
		#expect(clientConfig.nickname.isEmpty == false)
		#expect(clientConfig.channelList.isEmpty)
		#expect(clientConfig.identityClientSideCertificate == nil)
		#expect(clientConfig.awayNickname == "")
		#expect(clientConfig.proxyAddress == nil)

		let client = GLTTestClient()
		let connection = Connection(config: Glasstual.IRCConnectionConfig(), onClient: client)
		#expect(connection.client != nil)
		#expect(connection.uniqueIdentifier.isEmpty == false)
		#expect(connection.connectedAddress == nil)
	}

	@Test("The NSString hostmask accessors return the parsed components")
	func nsStringHostmaskAccessorsPreserveParsedComponents() {
		let source: NSString = "nick!user@example.test"

		#expect(source.nicknameFromHostmask == "nick")
		#expect(source.usernameFromHostmask == "user")
		#expect(source.addressFromHostmask == "example.test")
		#expect(("not a hostmask" as NSString).usernameFromHostmask == nil)
	}

	@Test("A complete control sequence is removed by both formatting entry points")
	func sharedFormattingRemovesCompleteControlSequences() {
		let formatted = "\u{02}bold\u{02} \u{03}04,12palette \u{04}A1B2C3,001122hex\u{0F}"
		let expected = "bold palette hex"

		#expect(IRCFormatting.removingControlCodes(from: formatted) == expected)
		#expect((formatted as NSString).stripIRCEffects == expected)
	}

	@Test("A malformed colour separator is left in the text")
	func sharedFormattingPreservesMalformedColorSeparatorsAndUnicode() {
		#expect(IRCFormatting.removingControlCodes(from: "\u{03}04,text") == ",text")
		#expect(IRCFormatting.removingControlCodes(from: "\u{04}AABBCC,no") == ",no")
		#expect(IRCFormatting.removingControlCodes(from: "\u{03},plain 😀") == ",plain 😀")
	}

	@Test("The hostmask parser keeps its validation rules")
	func sharedHostmaskParserPreservesValidationRules() throws {
		let hostmask = try #require(IRCHostmask(parsing: "nick!user@example.test"))

		#expect(hostmask.nickname == "nick")
		#expect(hostmask.username == "user")
		#expect(hostmask.address == "example.test")
		#expect(IRCHostmask(parsing: "*!user@example.test") == nil)
		#expect(IRCHostmask(parsing: "nick!user name@example.test") == nil)
		#expect(IRCHostmask(parsing: "long-nickname!user@example.test", maximumNicknameLength: 4) == nil)
	}
}
