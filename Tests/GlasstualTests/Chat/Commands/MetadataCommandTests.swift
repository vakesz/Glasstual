// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("/metadata")
struct MetadataCommandTests {
	@Test("A first word that is a subcommand targets the user")
	func targetDefaulting() throws {
		let own = try #require(MetadataCommandRequest(arguments: "set display-name Ada Lovelace"))
		#expect(own.target == "*")
		#expect(own.keys == ["display-name"])
		#expect(own.value == "Ada Lovelace")

		let other = try #require(MetadataCommandRequest(arguments: "#c get avatar color"))
		#expect(other.target == "#c")
		#expect(other.subcommand == .get)
		#expect(other.keys == ["avatar", "color"])

		#expect(MetadataCommandRequest(arguments: "#c nonsense") == nil)
	}

	@Test("set with \"\" sets the empty value, and set alone removes")
	func emptyLiteral() throws {
		#expect(try #require(MetadataCommandRequest(arguments: "set avatar \"\"")).value == "")
		#expect(try #require(MetadataCommandRequest(arguments: "set avatar")).value == nil)
	}

	@Test("Each subcommand sends its line", arguments: [
		("/metadata get display-name", "METADATA * GET display-name"),
		("/metadata #c list", "METADATA #c LIST"),
		("/metadata peer clear", "METADATA peer CLEAR"),
		("/metadata sub im.xmpp", "METADATA * SUB im.xmpp"),
		("/metadata unsub avatar", "METADATA * UNSUB avatar"),
		("/metadata subs", "METADATA * SUBS"),
		("/metadata #c sync", "METADATA #c SYNC"),
		("/metadata set color \"\"", "METADATA * SET color :"),
		("/metadata #c set url https://example.org", "METADATA #c SET url https://example.org"),
	])
	func wireLines(_ testCase: (input: String, line: String)) throws {
		let session = try makeMetadataSession(joined: false)

		session.sendCommand(testCase.input)

		#expect(session.wireLines.last == testCase.line)
	}

	@Test("An invalid key and too many subscriptions are refused before sending")
	func localRefusals() throws {
		let session = try makeMetadataSession(offer: "batch draft/metadata-2=max-subs=3", joined: false)
		let sent = session.wireLines.count

		session.sendCommand("/metadata get Avatar")
		session.sendCommand("/metadata sub a b c d")

		#expect(session.wireLines.count == sent)
	}

	@Test("A GET batch prints values and unset keys, and an empty LIST prints that there is none")
	func outputFormatting() throws {
		let session = try makeMetadataSession(joined: false)

		session.sendCommand("/metadata peer get display-name avatar")
		try session.receive(":irc.example.net BATCH +g metadata peer")
		try session.receive("@batch=g :irc.example.net 761 ada peer display-name * :Peer\u{202E} Name")
		try session.receive("@batch=g :irc.example.net 766 ada peer avatar :key not set")
		try session.receive(":irc.example.net BATCH -g")
		#expect(session.printedBodies.contains("display-name = Peer Name"))
		#expect(session.printedBodies.contains(String(localized: .Metadata.keyNotSet("avatar"))))

		session.sendCommand("/metadata #c list")
		try session.receive(":irc.example.net BATCH +l metadata #c")
		try session.receive(":irc.example.net BATCH -l")
		#expect(session.printedBodies.last == String(localized: .Metadata.noMetadata))
	}

	@Test("Without the capability the command says profiles are unsupported")
	func unsupported() {
		let session = makeRegistrationSession()

		session.sendCommand("/metadata list")

		#expect(session.printedBodies.last == String(localized: .Metadata.unsupported))
	}
}
