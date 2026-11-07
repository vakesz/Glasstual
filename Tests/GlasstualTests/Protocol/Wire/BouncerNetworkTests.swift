// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Bouncer network attributes")
struct BouncerNetworkTests {
	@Test("A listing line becomes a network with its attributes decoded")
	func parsesAttributes() throws {
		let network = try #require(BouncerNetwork(
			id: "12",
			attributeText: #"name=My\sNetwork;state=connected;host=irc.example.net;port=6697;tls=1;nickname=me;username=u;realname=Real\sName"#
		))

		#expect(network.id == "12")
		#expect(network.name == "My Network")
		#expect(network.displayName == "My Network")
		#expect(network.state == .connected)
		#expect(network.host == "irc.example.net")
		#expect(network.port == 6697)
		#expect(network.usesTLS == true)
		#expect(network.nickname == "me")
		#expect(network.username == "u")
		#expect(network.realName == "Real Name")
	}

	@Test("Applying attributes replaces some, removes those with empty values and leaves the rest")
	func applyMerges() throws {
		var network = try #require(BouncerNetwork(id: "1", attributeText: "name=A;state=connected;host=h;port=6697;tls=1;error=x"))

		network.apply(["state": "disconnected", "error": "", "port": "", "tls": "0"])

		#expect(network.name == "A")
		#expect(network.host == "h")
		#expect(network.state == .disconnected)
		#expect(network.error == nil)
		#expect(network.port == nil)
		#expect(network.usesTLS == false)
	}

	@Test("Unknown attributes and unknown states are ignored instead of failing the line")
	func ignoresWhatItDoesNotKnow() throws {
		let network = try #require(BouncerNetwork(id: "1", attributeText: "name=X;state=reticulating;flavour=mint"))

		#expect(network.name == "X")
		#expect(network.state == nil)
	}

	@Test("An error attribute that is empty means no error")
	func emptyErrorIsNoError() throws {
		let network = try #require(BouncerNetwork(id: "1", attributeText: "name=X;error="))

		#expect(network.error == nil)
	}

	@Test("The display name falls back to the host and then to the identifier")
	func displayNameFallsBack() throws {
		#expect(try #require(BouncerNetwork(id: "4", attributeText: "host=irc.example.net")).displayName == "irc.example.net")
		#expect(try #require(BouncerNetwork(id: "4", attributeText: "state=connected")).displayName == "4")
		#expect(try #require(BouncerNetwork(id: "4", attributeText: "name=")).displayName == "4")
	}

	@Test("Attributes are escaped like message tags and read back unchanged")
	func escapingRoundTrips() {
		let text = "semi;colon back\\slash\nline\rreturn"
		let serialized = BouncerNetworkAttributes.serialize([("name", text), ("host", "irc.example.net")])

		#expect(serialized.contains(" ") == false)
		#expect(serialized.contains("\n") == false)
		#expect(BouncerNetworkAttributes.parse(serialized)?["name"] == text)
		#expect(BouncerNetworkAttributes.parse(serialized)?["host"] == "irc.example.net")
	}

	@Test("An edit sends only the attributes it sets, in a stable order, with an empty value kept")
	func editAttributeText() {
		var edit = BouncerNetworkEdit()
		edit.name = "Libera Chat"
		edit.host = "irc.libera.chat"
		edit.port = 6697
		edit.usesTLS = false
		edit.nickname = ""

		#expect(edit.attributeText == #"name=Libera\sChat;host=irc.libera.chat;port=6697;tls=0;nickname="#)
		#expect(BouncerNetworkEdit().attributeText.isEmpty)
	}

	@Test("A password is sent as the pass attribute")
	func editPassword() {
		var edit = BouncerNetworkEdit()
		edit.password = "p;w d"

		#expect(edit.attributeText == #"pass=p\:w\sd"#)
	}

	@Test("Network identifiers are short tokens, and the deletion marker is not one",
	      arguments: [("1", true), ("net-2_a.b", true), ("", false), ("*", false), ("a b", false), ("a/b", false),
	                  ("é", false), (String(repeating: "x", count: 65), false), (String(repeating: "x", count: 64), true)])
	func identifierValidity(identifier: String, isValid: Bool) {
		#expect(BouncerNetworkAttributes.isValidNetworkIdentifier(identifier) == isValid)
	}

	@Test("A line with an invalid identifier is not a network")
	func invalidIdentifierIsRejected() {
		#expect(BouncerNetwork(id: "bad id", attributeText: "name=X") == nil)
		#expect(BouncerNetwork(id: "*", attributeText: "name=X") == nil)
	}

	@Test("A value, a key or an attribute count past its limit makes the whole list invalid")
	func limitsBoundTheList() {
		let longValue = String(repeating: "v", count: BouncerNetworkAttributes.maximumValueBytes + 1)
		let longKey = String(repeating: "k", count: BouncerNetworkAttributes.maximumKeyBytes + 1)
		let manyKeys = (0 ... BouncerNetworkAttributes.maximumAttributes).map { "k\($0)=v" }.joined(separator: ";")

		#expect(BouncerNetworkAttributes.parse("name=\(longValue)") == nil)
		#expect(BouncerNetworkAttributes.parse("\(longKey)=v") == nil)
		#expect(BouncerNetworkAttributes.parse(manyKeys) == nil)
		#expect(BouncerNetworkAttributes.parse("name=\(String(repeating: "v", count: BouncerNetworkAttributes.maximumValueBytes))") != nil)
	}
}
