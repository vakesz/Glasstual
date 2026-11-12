// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network

/** The loopback IRC servers the screenshot scenes connect to.

 Two listeners on 127.0.0.1 serve ``DemoScript``:
 - `direct`: Example Network, three channels and a direct message.
 - `bouncer`: a soju-style account whose two networks the application binds
   one connection each to with `BOUNCER BIND`.

 Unlike ``LoopbackPeer``, which checks every line a scenario's application
 sends, this server only has to look right: it answers what a registration and
 a join need and ignores the rest. Nothing here talks to a real server. Like
 every listener of the harness, these deliver their events on the main queue. */
final class DemoServer {
	private let direct: DemoListener
	private let bouncer: DemoListener
	/// The other end of the secure file transfer `marlow` offers.
	let transferPeer: DCCFixturePeer

	private(set) var directPort: UInt16 = 0
	private(set) var bouncerPort: UInt16 = 0

	init(corpora: URL) throws {
		direct = try DemoListener(role: .direct)
		bouncer = try DemoListener(role: .bouncerAccount)
		transferPeer = try DCCFixturePeer(
			cancel: false,
			tls: DCCFixtureTLS(corpora: corpora, rotatesCertificate: false),
			filenames: [DemoScript.transferFilename]
		)
		direct.passiveTransferAnswered = { [transferPeer] port in transferPeer.connect(to: port) }
	}

	func start() async throws {
		directPort = try await direct.start()
		bouncerPort = try await bouncer.start()
		_ = try await transferPeer.start()
	}

	func stop() {
		direct.stop()
		bouncer.stop()
		transferPeer.stop()
	}

	/// Sends the scripted reactions for `channel`, which a transcript only
	/// shows once its view exists.
	func sendReactions(for channel: String) {
		for client in direct.clients + bouncer.clients {
			client.sendReactions(for: channel)
		}
	}

	/// Has `channel` say the lines it kept back until the reader looked away.
	func sendUnseenLines(for channel: String) {
		for client in direct.clients + bouncer.clients {
			client.sendUnseenLines(for: channel)
		}
	}

	/// Has `marlow` offer the demo file over a passive `DCC SSEND`.
	func offerSecureTransfer() {
		for client in direct.clients {
			client.offerSecureTransfer()
		}
	}
}

private enum DemoRole {
	case direct
	case bouncerAccount
}

private enum DemoWire {
	static let host = "demo.example"
	/// The host every scripted person appears from.
	static let userHost = "users.example.net"
	/// The token of the passive file offer.
	static let transferToken = "7301"

	static func timestamp(minutesAgo: Int) -> String {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter.string(from: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60))
	}

	static func escapeTagValue(_ value: String) -> String {
		var result = ""
		for character in value {
			switch character {
			case ";": result += "\\:"
			case " ": result += "\\s"
			case "\\": result += "\\\\"
			default: result.append(character)
			}
		}
		return result
	}
}

private final class DemoListener {
	let role: DemoRole
	private let listener: NWListener
	private(set) var clients: [DemoClient] = []
	/// Called with the port the application listens on for the offered file.
	var passiveTransferAnswered: (UInt16) -> Void = { _ in }

	init(role: DemoRole) throws {
		self.role = role
		let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
		parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
		listener = try NWListener(using: parameters)
	}

	func start() async throws -> UInt16 {
		listener.newConnectionHandler = { [weak self] connection in
			Task { @MainActor in self?.accept(connection) }
		}
		listener.start(queue: .main)
		try await Wait.until("demo listener ready", timeout: .seconds(10)) { self.listener.state == .ready }
		guard let port = listener.port?.rawValue else { throw HarnessFailure.setup("Demo server port missing") }
		return port
	}

	func stop() {
		clients.forEach { $0.stop() }
		listener.cancel()
	}

	private func accept(_ connection: NWConnection) {
		let client = DemoClient(connection: connection, role: role)
		client.onClose = { [weak self] closed in self?.clients.removeAll { $0 === closed } }
		client.passiveTransferAnswered = { [weak self] port in self?.passiveTransferAnswered(port) }
		clients.append(client)
		client.start()
	}
}

/// One connection of the application to a demo listener.
private final class DemoClient {
	let connection: NWConnection
	let role: DemoRole
	private var pending = Data()
	private var nickname = ""
	private var boundNetwork: DemoNetwork?
	private var registered = false
	private var joined: [String: DemoChannel] = [:]
	var onClose: (DemoClient) -> Void = { _ in }
	var passiveTransferAnswered: (UInt16) -> Void = { _ in }

	private var network: DemoNetwork? {
		switch role {
		case .direct: DemoScript.example
		case .bouncerAccount: boundNetwork
		}
	}

	init(connection: NWConnection, role: DemoRole) {
		self.connection = connection
		self.role = role
	}

	func start() {
		connection.stateUpdateHandler = { [weak self] state in
			Task { @MainActor in
				guard let self else { return }
				switch state {
				case .failed, .cancelled: self.onClose(self)
				default: break
				}
			}
		}
		connection.start(queue: .main)
		receive()
	}

	func stop() {
		connection.cancel()
	}

	private func receive() {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
			Task { @MainActor in
				guard let self else { return }
				if let data, !data.isEmpty {
					self.pending.append(data)
					self.drain()
				}
				if done || error != nil {
					self.onClose(self)
				} else {
					self.receive()
				}
			}
		}
	}

	private func drain() {
		while let range = pending.range(of: Data("\r\n".utf8)) ?? pending.range(of: Data("\n".utf8)) {
			let line = String(bytes: pending[..<range.lowerBound], encoding: .utf8)
			pending.removeSubrange(..<range.upperBound)
			// A line that is not UTF-8 is nothing the demo answers.
			if let line {
				handle(line)
			}
		}
	}

	private var capabilitiesOffered: [String] {
		var offered = ["message-tags", "server-time", "batch", "multi-prefix"]
		if role == .bouncerAccount, boundNetwork == nil {
			offered += ["soju.im/bouncer-networks", "soju.im/bouncer-networks-notify"]
		}
		return offered
	}

	private func send(_ line: String, tags: [String: String] = [:]) {
		var text = line
		if !tags.isEmpty {
			let joinedTags = tags.sorted { $0.key < $1.key }
				.map { "\($0.key)=\(DemoWire.escapeTagValue($0.value))" }.joined(separator: ";")
			text = "@\(joinedTags) " + line
		}
		connection.send(content: Data((text + "\r\n").utf8), completion: .contentProcessed { _ in })
	}

	private func handle(_ raw: String) {
		var line = raw
		if line.hasPrefix("@"), let space = line.firstIndex(of: " ") {
			line = String(line[line.index(after: space)...])
		}
		var trailing: String?
		if let range = line.range(of: " :") {
			trailing = String(line[range.upperBound...])
			line = String(line[..<range.lowerBound])
		}
		var parts = line.split(separator: " ").map(String.init)
		guard !parts.isEmpty else { return }
		let command = parts.removeFirst().uppercased()
		if let trailing {
			parts.append(trailing)
		}

		switch command {
		case "CAP": handleCapability(parts)
		case "NICK":
			if let value = parts.first {
				nickname = value
			}
		case "BOUNCER": handleBouncer(parts)
		case "PING": send(":\(DemoWire.host) PONG \(DemoWire.host) :\(parts.last ?? "")")
		case "JOIN": handleJoin(parts)
		case "MODE": handleMode(parts)
		case "WHO": send(":\(DemoWire.host) 315 \(nickname) \(parts.first ?? "*") :End of WHO list")
		case "PRIVMSG": handleMessage(parts)
		default: break
		}
	}

	private func handleCapability(_ parts: [String]) {
		guard let subcommand = parts.first?.uppercased() else { return }
		let target = nickname.isEmpty ? "*" : nickname
		switch subcommand {
		case "LS":
			send(":\(DemoWire.host) CAP \(target) LS :\(capabilitiesOffered.joined(separator: " "))")
		case "REQ":
			send(":\(DemoWire.host) CAP \(target) ACK :\(parts.last ?? "")")
		case "END":
			finishRegistration()
		default: break
		}
	}

	private func handleBouncer(_ parts: [String]) {
		guard role == .bouncerAccount, let subcommand = parts.first?.uppercased() else { return }
		switch subcommand {
		case "BIND":
			if parts.count > 1, let entry = DemoScript.bouncerNetworks.first(where: { $0.0 == parts[1] }) {
				boundNetwork = entry.1
			}
		case "LISTNETWORKS":
			send(":\(DemoWire.host) BATCH +nets soju.im/bouncer-networks")
			for (identifier, network) in DemoScript.bouncerNetworks {
				send(
					":\(DemoWire.host) BOUNCER NETWORK \(identifier) "
						+ "name=\(DemoWire.escapeTagValue(network.name));state=connected",
					tags: ["batch": "nets"]
				)
			}
			send(":\(DemoWire.host) BATCH -nets")
		default: break
		}
	}

	private func finishRegistration() {
		guard !registered else { return }
		registered = true
		let name = network?.name ?? DemoScript.bouncerAccountName
		send(":\(DemoWire.host) 001 \(nickname) :Welcome to \(name), \(nickname)")
		send(":\(DemoWire.host) 002 \(nickname) :Your host is \(DemoWire.host)")
		send(
			":\(DemoWire.host) 005 \(nickname) NETWORK=\(network?.token ?? "Demo") "
				+ "CASEMAPPING=ascii CHANTYPES=# PREFIX=(ov)@+ CHANLIMIT=#:50 NICKLEN=30 :\(DemoScript.endOfConnectionLines)"
		)
		let messageOfTheDay = network?.messageOfTheDay ?? []
		if messageOfTheDay.isEmpty {
			send(":\(DemoWire.host) 422 \(nickname) :MOTD File is missing")
		} else {
			send(":\(DemoWire.host) 375 \(nickname) :- \(DemoWire.host) Message of the Day -")
			for line in messageOfTheDay {
				send(":\(DemoWire.host) 372 \(nickname) :- \(line)")
			}
			send(":\(DemoWire.host) 376 \(nickname) :End of /MOTD command.")
		}
		guard let network else { return }
		// A bouncer has its channels joined already; a direct server waits for JOIN.
		for channel in network.channels where role == .bouncerAccount {
			join(channel)
		}
		for line in network.directLines {
			say(line, to: nickname, channelName: nickname)
		}
	}

	private func handleJoin(_ parts: [String]) {
		guard let network, let names = parts.first else { return }
		for name in names.split(separator: ",").map(String.init) {
			if let channel = network.channels.first(where: { $0.name.lowercased() == name.lowercased() }) {
				join(channel)
			}
		}
	}

	private func handleMode(_ parts: [String]) {
		guard let target = parts.first, target.hasPrefix("#") else {
			send(":\(DemoWire.host) 221 \(nickname) :+i")
			return
		}
		if parts.count > 1, parts[1] == "b" || parts[1] == "+b" {
			send(":\(DemoWire.host) 368 \(nickname) \(target) :End of channel ban list")
		} else {
			send(":\(DemoWire.host) 324 \(nickname) \(target) +nt", tags: ["time": DemoWire.timestamp(minutesAgo: 240)])
		}
	}

	/// The application's answer to the passive file offer names the port it
	/// listens on: `DCC SSEND <file> <address> <port> <size> <token>`.
	private func handleMessage(_ parts: [String]) {
		guard parts.count == 2, parts[0] == DemoScript.transferSender else { return }
		let words = parts[1].replacingOccurrences(of: "\u{01}", with: "").split(separator: " ").map(String.init)
		guard words.count == 7, words[0] == "DCC", words[1] == "SSEND", words[6] == DemoWire.transferToken,
		      let port = UInt16(words[4]), port > 0
		else { return }
		passiveTransferAnswered(port)
	}

	private func join(_ channel: DemoChannel) {
		guard joined[channel.name] == nil else { return }
		joined[channel.name] = channel
		// Stamped before the first scripted line so the transcript reads in order.
		let early = ["time": DemoWire.timestamp(minutesAgo: 240)]
		send(":\(nickname)!\(nickname)@\(DemoWire.userHost) JOIN \(channel.name)", tags: early)
		send(":\(DemoWire.host) 332 \(nickname) \(channel.name) :\(channel.topic)", tags: early)
		send(":\(DemoWire.host) 353 \(nickname) = \(channel.name) :\(channel.members.joined(separator: " "))")
		send(":\(DemoWire.host) 366 \(nickname) \(channel.name) :End of NAMES list")
		for line in channel.seenLines {
			say(line, to: channel.name, channelName: channel.name)
		}
	}

	func sendUnseenLines(for channelName: String) {
		guard let channel = joined[channelName] else { return }
		for line in channel.unseenLines {
			say(line, to: channel.name, channelName: channel.name)
		}
	}

	private func messageIdentifier(_ identifier: String, channelName: String) -> String {
		"\(role == .direct ? "d" : "b")-\(channelName.dropFirst(channelName.hasPrefix("#") ? 1 : 0))-\(identifier)"
	}

	private func say(_ line: DemoLine, to target: String, channelName: String) {
		var tags = [
			"time": DemoWire.timestamp(minutesAgo: line.minutesAgo),
			"msgid": messageIdentifier(line.identifier, channelName: channelName),
		]
		if let replyTo = line.replyTo {
			tags["+draft/reply"] = messageIdentifier(replyTo, channelName: channelName)
		}
		let body = line.isAction ? "\u{01}ACTION \(line.text)\u{01}" : line.text
		send(":\(line.sender)!\(line.sender)@\(DemoWire.userHost) PRIVMSG \(target) :\(body)", tags: tags)
	}

	func sendReactions(for channelName: String) {
		guard let channel = joined[channelName] else { return }
		for reaction in channel.reactions {
			send(
				":\(reaction.sender)!\(reaction.sender)@\(DemoWire.userHost) TAGMSG \(channel.name)",
				tags: [
					"time": DemoWire.timestamp(minutesAgo: reaction.minutesAgo),
					"+draft/react": reaction.emoji,
					"+draft/reply": messageIdentifier(reaction.target, channelName: channel.name),
				]
			)
		}
	}

	/// 2130706433 is 127.0.0.1; port zero and a token make the offer passive,
	/// so the application listens and the peer dials it.
	func offerSecureTransfer() {
		guard registered else { return }
		let sender = DemoScript.transferSender
		send(
			":\(sender)!\(sender)@\(DemoWire.userHost) PRIVMSG \(nickname) :\u{01}DCC SSEND \(DemoScript.transferFilename) "
				+ "2130706433 0 \(DCCFixturePeer.size) \(DemoWire.transferToken)\u{01}"
		)
	}
}
