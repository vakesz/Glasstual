// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The `irc://` shapes a user actually pastes: an address in brackets with a
/// port, a channel behind a fragment, a channel that arrives percent-encoded,
/// and the key syntax the session does not support.
@Suite("Application link parsing")
struct ApplicationLinkParsingTests {
	private func connectionIntent(for location: String) -> ServerConnectionRequest? {
		guard case let .connect(request) = ApplicationLink.parse(location) else { return nil }
		return request
	}

	@Test("A bracketed IPv6 loopback keeps its explicit port")
	func loopbackWithPort() throws {
		let request = try #require(connectionIntent(for: "ircs://[::1]:6697/%23chat"))

		#expect(request.serverAddress == "::1")
		#expect(request.serverPort == 6697)
		#expect(request.connectSecurely)
		#expect(request.channels == ["#chat"])
	}

	@Test("A bracketed IPv6 address without a port takes the scheme's default")
	func loopbackWithoutPort() throws {
		let plain = try #require(connectionIntent(for: "irc://[::1]/chat"))
		#expect(plain.serverPort == UInt16(ConnectionDefaults.serverPort))
		#expect(plain.connectSecurely == false)

		let secured = try #require(connectionIntent(for: "ircs://[::1]/chat"))
		#expect(secured.serverPort == UInt16(ConnectionDefaults.serverPortSecure))
	}

	@Test("A channel written as a fragment names the same channel as a path")
	func fragmentChannels() throws {
		let fragment = try #require(connectionIntent(for: "irc://irc.example.test/#chat"))
		let path = try #require(connectionIntent(for: "irc://irc.example.test/%23chat"))

		#expect(fragment.channels == ["#chat"])
		#expect(fragment.channels == path.channels)
	}

	@Test("A fragment on top of a channel path is a contradiction and is refused")
	func fragmentAfterPathIsRejected() {
		#expect(ApplicationLink.parse("irc://irc.example.test/chat#other") == nil)
	}

	/** Channel keys are not carried.

	 The IRC URI draft puts a key in the query, and this parser refuses any
	 query rather than dropping the key and joining an unkeyed channel — which
	 would fail on the server with nothing said here. */
	@Test("A URI carrying a channel key is refused rather than silently unkeyed", arguments: [
		"irc://irc.example.test/chat?key",
		"irc://irc.example.test/chat?key=secret",
		"ircs://[::1]:6697/%23chat?key=secret",
	])
	func channelKeysAreRefused(location: String) {
		#expect(ApplicationLink.parse(location) == nil)
	}

	@Test("needssl upgrades a bracketed address without touching its port")
	func needsSecureUpgradeKeepsPort() throws {
		let request = try #require(connectionIntent(for: "irc://[::1]:6669/chat,needssl"))

		#expect(request.serverAddress == "::1")
		#expect(request.serverPort == 6669)
		#expect(request.connectSecurely)
		#expect(request.channels == ["#chat"])
	}

	/// A link a conversation shows may be written by anyone, so the ones that
	/// reveal a folder or connect are asked about, and the ones that only
	/// navigate inside the app are not.
	@Test("Only application links that reveal or connect need confirming", arguments: [
		("glasstual://application-support-folder", true),
		("glasstual://custom-scripts-folder", true),
		("glasstual://diagnostic-reports-folder", true),
		("glasstual://support-channel", true),
		("glasstual://testing-channel", true),
		("glasstual://acknowledgements", false),
		("glasstual://goto/ABC", false),
		("glasstual://nothing-by-this-name", false),
		("https://example.test/", false),
		("glasstual:malformed", false),
	] as [(String, Bool)])
	func confirmationIsForRevealAndConnect(location: String, expected: Bool) throws {
		let url = try #require(URL(string: location))

		#expect(ApplicationLink.requiresConfirmation(url) == expected)
	}
}
