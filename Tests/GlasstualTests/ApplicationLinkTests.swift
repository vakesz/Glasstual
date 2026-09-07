import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
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

	/// The connection half of a parsed link. Every case below is about what a
	/// URI asks a connection for, so unwrapping it once keeps the assertions
	/// about the request rather than about the enum.
	private func connectionIntent(for location: String) -> ServerConnectionRequest? {
		guard case let .connect(intent) = ApplicationLink.parse(location) else { return nil }
		return intent
	}

	@Test("Malformed authority and multiple path components are rejected")
	func malformedComponentsAreRejected() {
		#expect(connectionIntent(for: "irc:example") == nil)
		#expect(connectionIntent(for: "irc://a/b/c/d") == nil)
		#expect(connectionIntent(for: "") == nil)
		#expect(connectionIntent(for: "https://example.test/#chat") == nil)
	}

	@Test("A plain irc:// URI names the default port and the channel it asked for")
	func parseIRCProtocolURIAcceptsBasicIrcURL() throws {
		let request = try #require(connectionIntent(for: "irc://irc.example.test/#chat"))

		#expect(request.serverAddress == "irc.example.test")
		#expect(request.serverPort == 6667)
		#expect(request.connectSecurely == false)
		#expect(request.channels == ["#chat"])
	}

	@Test("An ircs:// URI keeps its explicit port and asks for a secured connection")
	func secureSchemeAndExplicitPortAreHonoured() throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test:7000/chat"))

		#expect(request.connectSecurely)
		#expect(request.serverPort == 7000)
		#expect(request.channels == ["#chat"])
		#expect(request.options == .externalLink)
	}

	@Test("TLS defaults are applied after needssl and never replace an explicit port")
	func securePortDefaults() throws {
		for location in ["ircs://irc.example.test", "irc://irc.example.test/chat,needssl"] {
			let request = try #require(connectionIntent(for: location))
			#expect(request.serverPort == 6697)
			#expect(request.connectSecurely)
		}
		let explicit = try #require(connectionIntent(for: "irc://irc.example.test:6669/chat,needssl"))
		#expect(explicit.serverPort == 6669)
		#expect(explicit.connectSecurely)
	}

	@Test("IPv6 and encoded channels stay typed without a command-string round trip")
	func decodedComponentsStaySeparate() throws {
		let request = try #require(connectionIntent(
			for: "ircs://[2001:db8::1]/%23chat,%26local,+modeless,!safe,%23a%2Fb"
		))
		#expect(request.serverAddress == "2001:db8::1")
		#expect(request.channels == ["#chat", "&local", "+modeless", "!safe", "#a/b"])
		#expect(request.serverPassword == nil)
		let once = try #require(connectionIntent(for: "irc://irc.example.test/%23percent%250A"))
		#expect(once.channels == ["#percent%0A"])
	}

	@Test("Unsafe channel and authority text is rejected, not silently rewritten", arguments: [
		"irc://irc.example.test:0/chat", "irc://irc.example.test:65536/chat",
		"irc://user:password@irc.example.test/chat", "irc://irc.example.test/chat?command=JOIN",
		"irc://irc.example.test/%23a%0D%0AJOIN%20%23b", "irc://irc.example.test/%23a%00b",
		"irc://irc.example.test/%23a%20b", "irc://irc.example.test/%23a%2Cb",
		"irc://irc.example.test/%23a%3Ab", "irc://irc.example.test/%GG",
		"irc://irc.example.test/chat#other", "irc://irc.example.test/%23",
	])
	func unsafeURLsAreRejected(location: String) {
		#expect(ApplicationLink.parse(location) == nil)
	}

	@Test("Application action aliases are typed and unknown plugin names remain inert")
	func applicationActions() {
		for alias in ["custom-scripts-folder", "unsupervised-script-folder", "unsupervised-scripts-folder"] {
			guard case let .applicationAction(action, source) = ApplicationLink.parse("glasstual://\(alias)") else {
				Issue.record("Expected an application action")
				return
			}
			#expect(action == .customScriptsFolder)
			#expect(source.host == alias)
		}
		#expect(ApplicationLink.Action(name: "contributors") == .acknowledgements)
		#expect(ApplicationLink.Action(name: "future-plugin-action") == .unknown("future-plugin-action"))
		guard case let .applicationAction(action, source) = ApplicationLink.parse("textual://goto/item%2Fname") else {
			Issue.record("Expected the legacy scheme to reach the typed adapter")
			return
		}
		#expect(action == .goto)
		#expect(source.absoluteString == "textual://goto/item%2Fname")
	}

	@Test("External links confirm reuse and preserve their no-connect options", arguments: [true, false])
	func reuseRequiresConfirmation(accept: Bool) throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let client = GLTTestClient()
		client.config.serverList = [Server(
			serverAddress: "irc.example.test",
			serverPort: 6697,
			prefersSecuredConnection: true
		)]
		var confirmations = 0
		var merged: [ServerConnectionRequest] = []
		var created: [ServerConnectionRequest] = []
		ServerConnectionCoordinator.connect(
			using: request,
			clients: [client],
			confirmMerge: { candidate, address, channels in
				#expect(candidate === client)
				#expect(address == request.serverAddress)
				#expect(channels == request.channels)
				confirmations += 1
				return accept
			},
			mergeConnection: { value, _ in merged.append(value) },
			createConnection: { created.append($0) }
		)
		#expect(confirmations == 1)
		#expect(merged == (accept ? [request] : []))
		#expect(created == (accept ? [] : [request]))
		#expect(request.options.connectWhenCreated == false)
	}

	@Test(
		"Hostname matches cannot reuse a different endpoint or TLS policy",
		arguments: ["port", "tls", "ciphers", "certificate"]
	)
	func mismatchedConnectionsAreNotOffered(kind: String) throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let client = GLTTestClient()
		client.config.serverList = [Server(
			serverAddress: "irc.example.test",
			serverPort: kind == "port" ? 7000 : 6697,
			prefersSecuredConnection: kind != "tls"
		)]
		if kind == "ciphers" {
			client.config.cipherSuites = .none
		}
		if kind == "certificate" {
			client.config.validateServerCertificateChain = false
		}
		var created = 0
		ServerConnectionCoordinator.connect(
			using: request,
			clients: [client],
			confirmMerge: { _, _, _ in Issue.record("Mismatched connection offered"); return true },
			mergeConnection: { _, _ in Issue.record("Mismatched connection reused") },
			createConnection: { value in
				#expect(value == request)
				created += 1
			}
		)
		#expect(created == 1)
	}

	@Test("The real merge path does not JOIN for an external link, even on a logged-in client")
	func externalMergeDoesNotJoin() throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let client = GLTTestClient()
		client.config.serverList = [Server(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		client.isLoggedIn = true
		let channel = IRCChannel(config: .seed(withName: "#chat"))
		channel.associatedClient = client
		client.add(channel)
		try #require(client.canJoin(channel))
		ServerConnectionCoordinator.connect(
			using: request,
			clients: [client],
			confirmMerge: { _, _, _ in true },
			createConnection: { _ in Issue.record("Expected reuse") }
		)
		#expect(channel.status != .joining)
		#expect(client.sentLines.count == 0)
		#expect(client.recordedOutput.selectedItems.isEmpty)

		let command = try #require(ServerConnectionRequest.parse(
			"-SSL irc.example.test:6697", channels: "#chat",
			options: ServerConnectionOptions(
				connectWhenCreated: true, mergeConnectionIfPossible: true, selectFirstChannelAdded: false
			)
		))
		ServerConnectionCoordinator.connect(
			using: command,
			clients: [client],
			confirmMerge: { _, _, _ in true },
			createConnection: { _ in Issue.record("Expected reuse") }
		)
		#expect(channel.status == .joining)
	}

	@Test("A matching saved endpoint cannot hide a different live socket")
	func liveEndpointMustAlsoMatch() throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let client = GLTTestClient()
		client.config.serverList = [Server(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		var socketConfig = IRCConnectionConfig()
		socketConfig.serverAddress = "other.example.test"
		socketConfig.serverPort = 6697
		socketConfig.connectionPrefersSecuredConnection = true
		socketConfig.connectionShouldValidateCertificateChain = true
		client.socket = Connection(config: socketConfig, onClient: client)
		defer { client.socket = nil }
		#expect(ServerConnectionCoordinator.canReuse(client, for: request) == false)
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
