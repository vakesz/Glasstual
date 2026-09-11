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

import Foundation
@testable import Glasstual
import Testing

/// The `irc://` shapes a user actually pastes: an address in brackets with a
/// port, a channel behind a fragment, a channel that arrives percent-encoded,
/// and the key syntax the client does not support.
@Suite("Application link parsing")
struct UIApplicationLinkParsingTests {
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
		#expect(plain.serverPort == UInt16(IRCConnectionDefaults.serverPort))
		#expect(plain.connectSecurely == false)

		let secured = try #require(connectionIntent(for: "ircs://[::1]/chat"))
		#expect(secured.serverPort == UInt16(IRCConnectionDefaults.serverPortSecure))
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
}
