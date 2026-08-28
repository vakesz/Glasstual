@testable import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
final class IRCExtrasMigrationTests: XCTestCase {
	func testParseIRCProtocolURIRejectsMalformedSlashCounts() {
		XCTAssertNil(IRCExtras.connectionIntent(forIRCProtocolURI: "irc:example"))
		XCTAssertNil(IRCExtras.connectionIntent(forIRCProtocolURI: "irc://a/b/c/d"))
		XCTAssertNil(IRCExtras.connectionIntent(forIRCProtocolURI: ""))
	}

	func testParseIRCProtocolURIAcceptsBasicIrcURL() throws {
		let intent = try XCTUnwrap(IRCExtras.connectionIntent(forIRCProtocolURI: "irc://irc.example.test/#chat"))

		XCTAssertEqual(intent.serverInfo, "irc.example.test:6667")
		XCTAssertEqual(intent.channelList, "#chat")

		let request = try XCTUnwrap(IRCExtras.connectionRequest(
			parsing: intent.serverInfo,
			channelList: intent.channelList,
			connectWhenCreated: false,
			mergeConnectionIfPossible: true,
			selectFirstChannelAdded: false
		))

		XCTAssertEqual(request.serverAddress, "irc.example.test")
		XCTAssertEqual(request.serverPort, 6667)
		XCTAssertFalse(request.connectSecurely)
		XCTAssertEqual(request.channelList, ["#chat"])
	}

	func testSecureSchemeAndExplicitPortAreHonoured() throws {
		let intent = try XCTUnwrap(IRCExtras.connectionIntent(forIRCProtocolURI: "ircs://irc.example.test:6697/chat"))

		XCTAssertEqual(intent.serverInfo, "-SSL irc.example.test:6697")
		XCTAssertEqual(intent.channelList, "#chat")

		let request = try XCTUnwrap(IRCExtras.connectionRequest(
			parsing: intent.serverInfo,
			channelList: intent.channelList,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		))

		XCTAssertTrue(request.connectSecurely)
		XCTAssertEqual(request.serverPort, 6697)
	}

	func testServerInfoParserRejectsGarbage() {
		XCTAssertNil(IRCExtras.connectionRequest(
			parsing: "",
			channelList: nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		))
		XCTAssertNil(IRCExtras.connectionRequest(
			parsing: "[not-an-ipv6]:6667",
			channelList: nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		))
		XCTAssertNil(IRCExtras.connectionRequest(
			parsing: "irc.example.test:99999",
			channelList: nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		))
	}
}
