@testable import Glasstual
import Testing

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
@Suite("IRC protocol URI handling")
struct IRCExtrasMigrationTests {
	@Test("A URI with the wrong number of slashes is not a connection intent")
	func parseIRCProtocolURIRejectsMalformedSlashCounts() {
		#expect(IRCExtras.connectionIntent(forIRCProtocolURI: "irc:example") == nil)
		#expect(IRCExtras.connectionIntent(forIRCProtocolURI: "irc://a/b/c/d") == nil)
		#expect(IRCExtras.connectionIntent(forIRCProtocolURI: "") == nil)
	}

	@Test("A plain irc:// URI names the default port and the channel it asked for")
	func parseIRCProtocolURIAcceptsBasicIrcURL() throws {
		let intent = try #require(IRCExtras.connectionIntent(forIRCProtocolURI: "irc://irc.example.test/#chat"))

		#expect(intent.serverInfo == "irc.example.test:6667")
		#expect(intent.channelList == "#chat")

		let request = try #require(IRCExtras.connectionRequest(
			parsing: intent.serverInfo,
			channelList: intent.channelList,
			connectWhenCreated: false,
			mergeConnectionIfPossible: true,
			selectFirstChannelAdded: false
		))

		#expect(request.serverAddress == "irc.example.test")
		#expect(request.serverPort == 6667)
		#expect(request.connectSecurely == false)
		#expect(request.channelList == ["#chat"])
	}

	@Test("An ircs:// URI keeps its explicit port and asks for a secured connection")
	func secureSchemeAndExplicitPortAreHonoured() throws {
		let intent = try #require(IRCExtras.connectionIntent(forIRCProtocolURI: "ircs://irc.example.test:6697/chat"))

		#expect(intent.serverInfo == "-SSL irc.example.test:6697")
		#expect(intent.channelList == "#chat")

		let request = try #require(IRCExtras.connectionRequest(
			parsing: intent.serverInfo,
			channelList: intent.channelList,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		))

		#expect(request.connectSecurely)
		#expect(request.serverPort == 6697)
	}

	@Test("Server info that is empty, malformed or out of port range is rejected")
	func serverInfoParserRejectsGarbage() {
		#expect(IRCExtras.connectionRequest(
			parsing: "",
			channelList: nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		) == nil)
		#expect(IRCExtras.connectionRequest(
			parsing: "[not-an-ipv6]:6667",
			channelList: nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		) == nil)
		#expect(IRCExtras.connectionRequest(
			parsing: "irc.example.test:99999",
			channelList: nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		) == nil)
	}
}
