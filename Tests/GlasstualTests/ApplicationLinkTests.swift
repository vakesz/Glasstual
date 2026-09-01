@testable import Glasstual
import Testing

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@MainActor
@Suite("Application links and server connection requests")
struct ApplicationLinkTests {
	private let externalLinkOptions = ServerConnectionOptions(
		connectWhenCreated: false,
		mergeConnectionIfPossible: true,
		selectFirstChannelAdded: false
	)

	@Test("A URI with the wrong number of slashes is not a connection intent")
	func parseIRCProtocolURIRejectsMalformedSlashCounts() {
		#expect(ApplicationLink.connectionIntent(for: "irc:example") == nil)
		#expect(ApplicationLink.connectionIntent(for: "irc://a/b/c/d") == nil)
		#expect(ApplicationLink.connectionIntent(for: "") == nil)
		#expect(ApplicationLink.connectionIntent(for: "https://example.test/#chat") == nil)
	}

	@Test("A plain irc:// URI names the default port and the channel it asked for")
	func parseIRCProtocolURIAcceptsBasicIrcURL() throws {
		let intent = try #require(ApplicationLink.connectionIntent(for: "irc://irc.example.test/#chat"))

		#expect(intent.serverInfo == "irc.example.test:6667")
		#expect(intent.channelList == "#chat")

		let request = try #require(ServerConnectionRequest.parse(
			intent.serverInfo,
			channels: intent.channelList,
			options: externalLinkOptions
		))

		#expect(request.serverAddress == "irc.example.test")
		#expect(request.serverPort == 6667)
		#expect(request.connectSecurely == false)
		#expect(request.channels == ["#chat"])
	}

	@Test("An ircs:// URI keeps its explicit port and asks for a secured connection")
	func secureSchemeAndExplicitPortAreHonoured() throws {
		let intent = try #require(ApplicationLink.connectionIntent(for: "ircs://irc.example.test:6697/chat"))

		#expect(intent.serverInfo == "-SSL irc.example.test:6697")
		#expect(intent.channelList == "#chat")

		let request = try #require(ServerConnectionRequest.parse(
			intent.serverInfo,
			channels: intent.channelList,
			options: externalLinkOptions
		))

		#expect(request.connectSecurely)
		#expect(request.serverPort == 6697)
	}

	@Test("Server info that is empty, malformed or out of port range is rejected")
	func serverInfoParserRejectsGarbage() {
		#expect(ServerConnectionRequest.parse(
			"",
			channels: nil,
			options: externalLinkOptions
		) == nil)
		#expect(ServerConnectionRequest.parse(
			"[not-an-ipv6]:6667",
			channels: nil,
			options: externalLinkOptions
		) == nil)
		#expect(ServerConnectionRequest.parse(
			"irc.example.test:99999",
			channels: nil,
			options: externalLinkOptions
		) == nil)
	}
}
