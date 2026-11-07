// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Replays `Tests/Corpora/Soju/bouncer-networks.txt` through a session and
/// checks the lines the session writes against the transcript.
@MainActor
@Suite("soju bouncer-networks transcripts")
struct SojuTranscriptTests {
	private enum Step {
		case server(String)
		case acknowledge
		case expect(String)
	}

	private static func scenario(named name: String) throws -> [Step] {
		let url = RepositoryPaths.corpora.appending(path: "Soju/bouncer-networks.txt")
		let text = try String(contentsOf: url, encoding: .utf8)
		var steps: [Step] = []
		var isInScenario = false
		for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
			if line.hasPrefix("== ") {
				isInScenario = line.dropFirst(3) == name
			} else if isInScenario {
				if line.hasPrefix("S ") {
					steps.append(.server(String(line.dropFirst(2))))
				} else if line == "A" {
					steps.append(.acknowledge)
				} else if line.hasPrefix("C ") {
					steps.append(.expect(String(line.dropFirst(2))))
				}
			}
		}
		return steps
	}

	private func session(
		binding: BouncerNetworkBinding? = nil,
		fixture: ChatEnvironmentFixture = ChatEnvironmentFixture()
	) -> TestServerSession {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "username": "me"], nicknamePassword: nil, fixture: fixture
		)
		session.config.bouncerNetwork = binding
		session.forwardsProcessedMessages = true
		session.forwardsSentLines = true
		session.setConnectionTransportForTesting(.connected)
		return session
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		if session.filterBatchCommandIncomingData(message) {
			return
		}
		if message.commandNumeric > 0 {
			session.receiveNumericReply(message)
		} else {
			session.processIncomingMessage(message)
		}
	}

	/// Answers every `CAP REQ` the way a bouncer would, until it stops being asked.
	private func acknowledge(on session: TestServerSession) throws {
		var answered = 0
		for _ in 0 ..< 10 {
			let requests = sentLines(of: session).filter { $0.hasPrefix("CAP REQ") }
			guard requests.count > answered else { return }
			for request in requests[answered...] {
				let names = request.dropFirst("CAP REQ ".count).drop { $0 == ":" }
				try receive(":bnc.example CAP me ACK :\(names)", on: session)
			}
			answered = requests.count
		}
	}

	private func replay(_ name: String, on session: TestServerSession) throws {
		var consumed = 0
		for step in try Self.scenario(named: name) {
			switch step {
			case let .server(line):
				try receive(line, on: session)
			case .acknowledge:
				try acknowledge(on: session)
			case let .expect(line):
				let sent = sentLines(of: session).filter { $0.hasPrefix("BOUNCER ") || $0 == "CAP END" }
				#expect(sent.count > consumed, "\(line) was never sent; sent \(sent)")
				if sent.count > consumed {
					#expect(sent[consumed] == line)
				}
				consumed += 1
			}
		}
	}

	@Test("The transcript file has its scenarios")
	func transcriptIsNotEmpty() throws {
		#expect(try Self.scenario(named: "parent").count > 5)
		#expect(try Self.scenario(named: "network").count > 2)
	}

	@Test("An account connection lists its networks and follows the notifications")
	func parentListsAndFollows() throws {
		let session = session()

		try replay("parent", on: session)

		#expect(session.isCapabilityEnabled(.bouncerNetworks))
		#expect(session.isCapabilityEnabled(.bouncerNetworksNotify))
		#expect(session.bouncer.networks.networks.map(\.displayName) == ["My OFTC", "Rizon"])
		#expect(session.bouncer.networks.networks.map(\.state) == [.connected, .connecting])
	}

	@Test("A state-only notification keeps the name and host, and an empty value removes the error")
	func partialNotificationMerges() throws {
		let session = session()

		try replay("parent", on: session)

		let oftc = try #require(session.bouncer.networks.network(withIdentifier: "2"))
		#expect(oftc.name == "My OFTC")
		#expect(oftc.host == "irc.oftc.net")
		#expect(oftc.state == .connected)
		#expect(oftc.error == nil)
	}

	@Test("A network of the account is listed with its escaped name and error decoded")
	func listingDecodesAttributes() throws {
		let session = session()
		var steps = try Self.scenario(named: "parent")
		steps.removeLast(3)

		for step in steps {
			if case let .server(line) = step {
				try receive(line, on: session)
			} else if case .acknowledge = step {
				try acknowledge(on: session)
			}
		}

		let second = try #require(session.bouncer.networks.network(withIdentifier: "2"))
		#expect(second.name == "My OFTC")
		#expect(second.error == "Connection refused")
		#expect(second.state == .disconnected)
		#expect(session.bouncer.networks.network(withIdentifier: "1")?.usesTLS == true)
	}

	@Test("A network connection binds to its network before it ends negotiation")
	func networkBindsBeforeCapabilityEnd() throws {
		let session = session(binding: BouncerNetworkBinding(parentIdentifier: "parent", networkIdentifier: "7"))

		try replay("network", on: session)

		#expect(session.isCapabilityEnabled(.bouncerNetworks) == false)
		#expect(sentLines(of: session).contains { $0.hasPrefix("CAP REQ") && $0.contains("soju.im/bouncer-networks") } == false)
	}

	@Test("An account whose owner switched discovery off never asks for the capability")
	func discoveryOffRequestsNothing() throws {
		let session = session()
		session.config.bouncerDiscoversNetworks = false

		try receive(
			":bnc.example CAP * LS :batch message-tags soju.im/bouncer-networks soju.im/bouncer-networks-notify",
			on: session
		)
		try acknowledge(on: session)

		#expect(session.isCapabilityEnabled(.bouncerNetworks) == false)
		#expect(sentLines(of: session).contains { $0.contains("soju.im/bouncer-networks") } == false)
		#expect(sentLines(of: session).contains("CAP END"))
	}

	@Test("The account connection is a parent and lists nothing once discovery is off")
	func listingIsRefusedWhenDiscoveryIsOff() throws {
		let session = session()
		try replay("parent", on: session)
		session.config.bouncerDiscoversNetworks = false
		let before = session.bouncer.networks

		try receive(":bnc.example BOUNCER NETWORK 9 name=Late", on: session)

		#expect(session.bouncer.networks == before)
	}

	@Test("A hostile network line is ignored")
	func hostileLinesAreIgnored() throws {
		let session = session()
		try replay("parent", on: session)
		let before = session.bouncer.networks
		let longValue = String(repeating: "x", count: BouncerNetworkAttributes.maximumValueBytes + 1)

		try receive(":bnc.example BOUNCER NETWORK bad\\sid name=X", on: session)
		try receive(":bnc.example BOUNCER NETWORK 9 name=\(longValue)", on: session)

		#expect(session.bouncer.networks == before)
	}

	@Test("A failed management command is remembered for the pane that sent it")
	func failureIsRecorded() throws {
		let session = session()
		try replay("parent", on: session)

		try receive(":bnc.example FAIL BOUNCER INVALID_NETID 99 :Unknown network", on: session)

		#expect(session.bouncer.lastFailure == BouncerFailure(code: "INVALID_NETID", description: "Unknown network"))
		session.deleteBouncerNetwork("1")
		#expect(session.bouncer.lastFailure == nil)
		#expect(sentLines(of: session).last == "BOUNCER DELNETWORK 1")
	}

	@Test("Management commands go out with escaped attributes, and without notify the list is asked for again")
	func managementCommands() throws {
		let session = session()
		try receive(":bnc.example CAP * LS :batch soju.im/bouncer-networks", on: session)
		try acknowledge(on: session)
		session.markAsLoggedIn()
		var edit = BouncerNetworkEdit()
		edit.name = "My Net"
		edit.host = "irc.example.net"

		session.addBouncerNetwork(edit)
		session.changeBouncerNetwork("5", with: edit)
		try receive(":bnc.example BOUNCER ADDNETWORK 5", on: session)

		let sent = sentLines(of: session).filter { $0.hasPrefix("BOUNCER ") }
		#expect(sent == [
			#"BOUNCER ADDNETWORK name=My\sNet;host=irc.example.net"#,
			#"BOUNCER CHANGENETWORK 5 name=My\sNet;host=irc.example.net"#,
			"BOUNCER LISTNETWORKS",
		])
	}
}
