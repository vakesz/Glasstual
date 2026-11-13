// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

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

	@Test("Application action aliases are typed and unknown action names remain inert")
	func applicationActions() {
		guard case let .applicationAction(scriptsAction, scriptsSource) =
			ApplicationLink.parse("glasstual://custom-scripts-folder")
		else {
			Issue.record("Expected an application action")
			return
		}
		#expect(scriptsAction == .customScriptsFolder)
		#expect(scriptsSource.host == "custom-scripts-folder")
		#expect(ApplicationLink.Action(name: "unsupervised-scripts-folder") == .unknown("unsupervised-scripts-folder"))
		#expect(ApplicationLink.Action(name: "contributors") == .acknowledgements)
		#expect(ApplicationLink.Action(name: "future-action") == .unknown("future-action"))
		guard case let .applicationAction(action, source) = ApplicationLink.parse("glasstual://goto/item%2Fname") else {
			Issue.record("Expected the application scheme to reach the typed adapter")
			return
		}
		#expect(action == .goto)
		#expect(source.absoluteString == "glasstual://goto/item%2Fname")
		#expect(ApplicationLink.parse("textual://goto/item%2Fname") == nil)
	}

	@Test(
		"External links confirm reuse and preserve their no-connect options",
		arguments: [
			ServerConnectionMergeChoice.useExisting,
			.createNew,
			.cancel,
		]
	)
	func reuseRequiresConfirmation(choice: ServerConnectionMergeChoice) async throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test",
			serverPort: 6697,
			prefersSecuredConnection: true
		)]
		var confirmations = 0
		var merged: [ServerConnectionRequest] = []
		var created: [ServerConnectionRequest] = []
		await ServerConnectionResolution.resolve(
			using: request,
			sessions: { [session] },
			confirmMerge: { candidate, address, channels in
				#expect(candidate === session)
				#expect(address == request.serverAddress)
				#expect(channels == request.channels)
				confirmations += 1
				return choice
			},
			mergeConnection: { value, _ in merged.append(value) },
			createConnection: { created.append($0) }
		)
		#expect(confirmations == 1)
		#expect(merged == (choice == .useExisting ? [request] : []))
		#expect(created == (choice == .createNew ? [request] : []))
		#expect(request.options.connectWhenCreated == false)
	}

	@Test(
		"Hostname matches cannot reuse a different endpoint or TLS policy",
		arguments: ["port", "tls", "ciphers", "certificate"]
	)
	func mismatchedConnectionsAreNotOffered(kind: String) async throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test",
			serverPort: kind == "port" ? 7000 : 6697,
			prefersSecuredConnection: kind != "tls"
		)]
		if kind == "ciphers" {
			session.config.cipherSuites = .modern
		}
		if kind == "certificate" {
			session.config.validateServerCertificateChain = false
		}
		var created = 0
		await ServerConnectionResolution.resolve(
			using: request,
			sessions: { [session] },
			confirmMerge: { _, _, _ in
				Issue.record("Mismatched connection offered")
				return .useExisting
			},
			mergeConnection: { _, _ in Issue.record("Mismatched connection reused") },
			createConnection: { value in
				#expect(value == request)
				created += 1
			}
		)
		#expect(created == 1)
	}

	@Test("The real merge path does not JOIN for an external link, even on a logged-in session")
	func externalMergeDoesNotJoin() async throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		session.isLoggedIn = true
		let channel = Conversation(config: .seed(withName: "#chat"))
		channel.associatedSession = session
		session.add(channel)
		try #require(session.canJoin(channel))
		await ServerConnectionResolution.resolve(
			using: request,
			sessions: { [session] },
			confirmMerge: { _, _, _ in .useExisting },
			createConnection: { _ in Issue.record("Expected reuse") }
		)
		#expect(channel.status != .joining)
		#expect(session.sentLines.count == 0)
		#expect(session.recordedOutput.selectedItems.isEmpty)

		let command = try #require(ServerConnectionRequest.parse(
			"-SSL irc.example.test:6697", channels: "#chat",
			options: ServerConnectionOptions(
				connectWhenCreated: true, mergeConnectionIfPossible: true, selectFirstChannelAdded: false
			)
		))
		await ServerConnectionResolution.resolve(
			using: command,
			sessions: { [session] },
			confirmMerge: { _, _, _ in .useExisting },
			createConnection: { _ in Issue.record("Expected reuse") }
		)
		#expect(channel.status == .joining)
	}

	@Test("An endpoint edit invalidates reuse but does not cancel an explicit new connection",
	      arguments: [ServerConnectionMergeChoice.useExisting, .createNew])
	func changedEndpointInvalidatesPendingConfirmation(_ choice: ServerConnectionMergeChoice) async throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		var created = false
		await ServerConnectionResolution.resolve(
			using: request,
			sessions: { [session] },
			confirmMerge: { _, _, _ in
				session.config.serverList[0].serverAddress = "replacement.invalid"
				return choice
			},
			mergeConnection: { _, _ in Issue.record("A stale answer reused the changed endpoint") },
			createConnection: { _ in created = true }
		)
		#expect(created == (choice == .createNew))
	}

	@Test("Removing a server while a reuse prompt is open cancels the merge")
	func removedSessionInvalidatesConfirmation() async throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		var sessions: [ServerSession] = [session]
		await ServerConnectionResolution.resolve(
			using: request,
			sessions: { sessions },
			confirmMerge: { _, _, _ in
				sessions.removeAll()
				return .useExisting
			},
			mergeConnection: { _, _ in Issue.record("Removed server was reused") },
			createConnection: { _ in Issue.record("Cancelled merge created a new server") }
		)
	}

	@Test("Terminating sessions cannot be reused by server-only links")
	func terminatingSessionIsNotReused() throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		session.isTerminating = true
		#expect(!ServerConnectionResolution.canReuse(session, for: request))
	}

	@Test("A matching saved endpoint cannot hide a different live socket")
	func liveEndpointMustAlsoMatch() throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test/chat"))
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]
		var socketConfig = ConnectionConfig()
		socketConfig.serverAddress = "other.example.test"
		socketConfig.serverPort = 6697
		socketConfig.connectionPrefersSecuredConnection = true
		socketConfig.connectionShouldValidateCertificateChain = true
		session.socket = Connection(config: socketConfig, onSession: session)
		defer { session.socket = nil }
		#expect(ServerConnectionResolution.canReuse(session, for: request) == false)
	}

	@Test("Malformed server commands are rejected", arguments: [
		"", "[not-an-ipv6]:6667", "irc.example.test:99999", "[::1]junk", "[::1]junk 6667",
		"[::1]:", "[::1]:0", "[::1]:99999",
	])
	func serverInfoParserRejectsGarbage(input: String) {
		#expect(ServerConnectionRequest.parse(input, channels: nil, options: externalLinkOptions) == nil)
	}

	@Test("Bracketed IPv6 commands preserve their port and password", arguments: [
		"-TLS [::1]:6697 secret", "[::1] +6697 secret"
	])
	func bracketedIPv6Command(input: String) {
		#expect(ServerConnectionRequest.parse(input, channels: nil, options: externalLinkOptions) == ServerConnectionRequest(
			serverAddress: "::1", serverPort: 6697, serverPassword: "secret", connectSecurely: true,
			channels: [], options: externalLinkOptions
		))
	}

	/// A link naming only a server skipped the search for a saved one, so each
	/// click saved another copy of a server the reader already had.
	@Test("A link to a saved server opens that server instead of saving it again")
	func serverOnlyLinkReusesTheSavedServer() async throws {
		let request = try #require(connectionIntent(for: "ircs://irc.example.test"))
		try #require(request.channels.isEmpty)
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true
		)]

		await ServerConnectionResolution.resolve(
			using: request,
			sessions: { [session] },
			confirmMerge: { _, _, _ in
				Issue.record("A link with no channel to add has nothing to confirm")
				return .cancel
			},
			createConnection: { _ in Issue.record("The link saved a duplicate server") }
		)

		#expect(session.recordedOutput.selectedItems.map(ObjectIdentifier.init) == [ObjectIdentifier(session)])
		#expect(session.sentLines.count == 0)
	}
}
