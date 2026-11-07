// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

// Loopback IRC servers for scripts/website-screenshots.sh.
//
// Two listeners on 127.0.0.1 serve a fictional, friendly conversation:
//   - "direct": Example Network, three channels and a direct message.
//   - "bouncer": a soju-style account whose two networks the app binds one
//     connection each to with BOUNCER BIND.
// Nothing here talks to a real server. Usage:
//   website-demo-server <state-directory>
// The server writes "direct-port" and "bouncer-port" into the state directory
// once both listen, and reads commands from the "control" file there:
//   react <channel>   sends the scripted reactions for that channel, which a
//                     transcript only shows once its view exists.

import Foundation
import Network

// MARK: - Script

struct ScriptedLine {
	let identifier: String
	let sender: String
	let text: String
	let minutesAgo: Int
	var replyTo: String?
	var isAction = false
}

struct ScriptedReaction {
	let sender: String
	let emoji: String
	let target: String
	let minutesAgo: Int
}

struct ScriptedChannel {
	let name: String
	let topic: String
	let members: [String]
	let lines: [ScriptedLine]
	let reactions: [ScriptedReaction]
}

struct ScriptedNetwork {
	let name: String
	let nickname: String
	let channels: [ScriptedChannel]
	/// Lines said to the user directly once registration ends.
	let directLines: [ScriptedLine]
}

enum Script {
	static let nickname = "casey"

	static let example = ScriptedNetwork(
		name: "Example Network",
		nickname: nickname,
		channels: [swift, macdev, design],
		directLines: [
			ScriptedLine(
				identifier: "d1", sender: "marlow", text: "Hey Casey, are you joining the demo tonight?", minutesAgo: 12
			),
			ScriptedLine(
				identifier: "d2", sender: "marlow", text: "I will share the slides here before we start.", minutesAgo: 11
			),
		]
	)

	static let swift = ScriptedChannel(
		name: "#swift",
		topic: "Swift language talk. Be kind, be curious. https://example.com/swift-guidelines",
		members: ["@jordan", "@riley", "+sam", "kai", "marlow", "noor", nickname],
		lines: [
			ScriptedLine(
				identifier: "s1", sender: "jordan",
				text: "Morning all! Has anyone tried typed throws in a real project yet?", minutesAgo: 44
			),
			ScriptedLine(
				identifier: "s2", sender: "riley",
				text: "Yes, I replaced a few error enums with it. The call sites got much clearer.", minutesAgo: 41
			),
			ScriptedLine(
				identifier: "s3", sender: "sam",
				text: "jordan: Same here. Migrating was painless once the package dropped its old language mode.",
				minutesAgo: 38, replyTo: "s1"
			),
			ScriptedLine(
				identifier: "s4", sender: "marlow",
				text: "casey: your write-up on actor isolation helped me untangle a Sendable warning, thank you!",
				minutesAgo: 31
			),
			ScriptedLine(
				identifier: "s5", sender: nickname,
				text: "marlow: Glad it helped! Keeping the mutable state in one actor was the whole trick.",
				minutesAgo: 29, replyTo: "s4"
			),
			ScriptedLine(
				identifier: "s6", sender: "kai", text: "waves a copy of the new concurrency cheat sheet",
				minutesAgo: 24, isAction: true
			),
			ScriptedLine(
				identifier: "s7", sender: "jordan",
				text: "Notes from last week's meetup: https://example.com/swift-meetup-notes", minutesAgo: 17
			),
			ScriptedLine(
				identifier: "s8", sender: "noor", text: "Thanks for posting these, jordan. The slides were great.",
				minutesAgo: 9
			),
			ScriptedLine(
				identifier: "s9", sender: "riley", text: "Has anyone benchmarked the new string processing APIs?", minutesAgo: 6
			),
			ScriptedLine(
				identifier: "s10", sender: "jordan",
				text: "riley: Not yet, but I saw promising numbers for large inputs.", minutesAgo: 4, replyTo: "s9"
			),
			ScriptedLine(
				identifier: "s11", sender: "sam", text: "I will share a small benchmark project this afternoon.", minutesAgo: 2
			),
		],
		reactions: [
			ScriptedReaction(sender: "riley", emoji: "👍", target: "s4", minutesAgo: 30),
			ScriptedReaction(sender: "jordan", emoji: "❤️", target: "s4", minutesAgo: 30),
			ScriptedReaction(sender: "sam", emoji: "🎉", target: "s7", minutesAgo: 16),
			ScriptedReaction(sender: "kai", emoji: "👍", target: "s7", minutesAgo: 15),
		]
	)

	static let macdev = ScriptedChannel(
		name: "#macdev",
		topic: "Building apps for the Mac. Share tips, ask questions.",
		members: ["@devon", "+avery", "quinn", "riley", nickname],
		lines: [
			ScriptedLine(
				identifier: "m1", sender: "devon",
				text: "Anyone have a good pattern for restoring window state with SwiftUI scenes?", minutesAgo: 58
			),
			ScriptedLine(
				identifier: "m2", sender: "avery",
				text: "I keep the selection in the model and restore it on launch. Works every time.",
				minutesAgo: 52, replyTo: "m1"
			),
			ScriptedLine(
				identifier: "m3", sender: "quinn", text: "Menu commands feel so much better once focus is predictable.",
				minutesAgo: 20
			),
		],
		reactions: []
	)

	static let design = ScriptedChannel(
		name: "#design",
		topic: "Interface design, typography and craft.",
		members: ["@noor", "+sam", "avery", "kai", nickname],
		lines: [
			ScriptedLine(
				identifier: "g1", sender: "noor",
				text: "Reminder: the system materials look best when you let them do the work.", minutesAgo: 70
			),
			ScriptedLine(
				identifier: "g2", sender: "kai",
				text: "Agreed. Fewer custom backgrounds, more space and good type.", minutesAgo: 66
			),
		],
		reactions: []
	)

	// Networks a bouncer account owns.

	static let workshop = ScriptedNetwork(
		name: "Workshop Chat",
		nickname: nickname,
		channels: [
			ScriptedChannel(
				name: "#swiftui",
				topic: "SwiftUI layouts, state and animation.",
				members: ["@riley", "+devon", "jordan", nickname],
				lines: [
					ScriptedLine(
						identifier: "w1", sender: "riley", text: "The new toolbar spacing is a nice touch.", minutesAgo: 35
					),
					ScriptedLine(
						identifier: "w2", sender: "devon", text: "Agreed, and sidebars just work now.", minutesAgo: 33
					),
					ScriptedLine(
						identifier: "w3", sender: "jordan", text: "Has anyone tried the new glass effects in a custom toolbar?",
						minutesAgo: 27
					),
					ScriptedLine(
						identifier: "w4", sender: "riley",
						text: "jordan: Yes, they look great as long as you keep the content simple.", minutesAgo: 25,
						replyTo: "w3"
					),
					ScriptedLine(
						identifier: "w5", sender: "devon", text: "casey, did you see the new layout guide?", minutesAgo: 14
					),
					ScriptedLine(
						identifier: "w6", sender: "devon", text: "https://example.com/layout-guide has the details.",
						minutesAgo: 13
					),
				],
				reactions: []
			),
			ScriptedChannel(
				name: "#accessibility",
				topic: "Make it work for everyone.",
				members: ["@avery", "noor", nickname],
				lines: [
					ScriptedLine(
						identifier: "a1", sender: "avery", text: "Keyboard navigation first, then everything else.",
						minutesAgo: 80
					),
				],
				reactions: []
			),
		],
		directLines: []
	)

	static let openSource = ScriptedNetwork(
		name: "Open Source Hub",
		nickname: nickname,
		channels: [
			ScriptedChannel(
				name: "#contributors",
				topic: "Welcome, new contributors!",
				members: ["@sam", "+kai", "quinn", nickname],
				lines: [
					ScriptedLine(
						identifier: "o1", sender: "sam", text: "Good first issues are labeled in the tracker.",
						minutesAgo: 90
					),
				],
				reactions: []
			),
			ScriptedChannel(
				name: "#releases",
				topic: "Release announcements.",
				members: ["@kai", nickname],
				lines: [
					ScriptedLine(
						identifier: "r1", sender: "kai", text: "Version 2.4 is out. Release notes are on the site.",
						minutesAgo: 120
					),
				],
				reactions: []
			),
		],
		directLines: []
	)

	static let bouncerNetworks = [("1", workshop), ("2", openSource)]
}

// MARK: - Wire

func isoTimestamp(minutesAgo: Int) -> String {
	let date = Date(timeIntervalSinceNow: -Double(minutesAgo) * 60)
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	return formatter.string(from: date)
}

func escapeTagValue(_ value: String) -> String {
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

// MARK: - Connections

enum Role {
	case direct
	case bouncerAccount
}

@MainActor
final class Client {
	let connection: NWConnection
	let role: Role
	private var pending = Data()
	private var nickname = ""
	private var enabledCapabilities: Set<String> = []
	private var boundNetwork: ScriptedNetwork?
	private var registered = false
	private var network: ScriptedNetwork? {
		switch role {
		case .direct: Script.example
		case .bouncerAccount: boundNetwork
		}
	}

	private var joined: [String: ScriptedChannel] = [:]
	var onClose: (Client) -> Void = { _ in }

	init(connection: NWConnection, role: Role) {
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
		connection.start(queue: .global())
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
			let line = String(decoding: pending[..<range.lowerBound], as: UTF8.self)
			pending.removeSubrange(..<range.upperBound)
			handle(line)
		}
	}

	private var capabilitiesOffered: [String] {
		var offered = ["message-tags", "server-time", "batch", "multi-prefix"]
		if role == .bouncerAccount, boundNetwork == nil {
			offered += ["soju.im/bouncer-networks", "soju.im/bouncer-networks-notify"]
		}
		return offered
	}

	func send(_ line: String, tags: [String: String] = [:]) {
		var text = line
		if !tags.isEmpty {
			let joinedTags = tags.sorted { $0.key < $1.key }
				.map { "\($0.key)=\(escapeTagValue($0.value))" }.joined(separator: ";")
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
		if let trailing { parts.append(trailing) }

		switch command {
		case "CAP": handleCapability(parts)
		case "NICK":
			if let value = parts.first { nickname = value }
		case "BOUNCER": handleBouncer(parts)
		case "PING": send(":demo.example PONG demo.example :\(parts.last ?? "")")
		case "JOIN": handleJoin(parts)
		case "MODE": handleMode(parts)
		case "WHO": send(":demo.example 315 \(nickname) \(parts.first ?? "*") :End of WHO list")
		case "PRIVMSG", "TAGMSG", "PONG", "USER", "AWAY", "QUIT", "PART", "ISON", "MONITOR": break
		default: break
		}
	}

	private func handleCapability(_ parts: [String]) {
		guard let subcommand = parts.first?.uppercased() else { return }
		switch subcommand {
		case "LS":
			let target = nickname.isEmpty ? "*" : nickname
			send(":demo.example CAP \(target) LS :\(capabilitiesOffered.joined(separator: " "))")
		case "REQ":
			let requested = (parts.last ?? "").split(separator: " ").map(String.init)
			enabledCapabilities.formUnion(requested)
			send(":demo.example CAP \(nickname.isEmpty ? "*" : nickname) ACK :\(requested.joined(separator: " "))")
		case "END":
			finishRegistration()
		default: break
		}
	}

	private func handleBouncer(_ parts: [String]) {
		guard role == .bouncerAccount, let subcommand = parts.first?.uppercased() else { return }
		switch subcommand {
		case "BIND":
			if parts.count > 1, let entry = Script.bouncerNetworks.first(where: { $0.0 == parts[1] }) {
				boundNetwork = entry.1
			}
		case "LISTNETWORKS":
			send(":demo.example BATCH +nets soju.im/bouncer-networks")
			for (identifier, network) in Script.bouncerNetworks {
				send(
					":demo.example BOUNCER NETWORK \(identifier) name=\(escapeTagValue(network.name));state=connected",
					tags: ["batch": "nets"]
				)
			}
			send(":demo.example BATCH -nets")
		default: break
		}
	}

	private func finishRegistration() {
		guard !registered else { return }
		registered = true
		let name = network?.name ?? "Demo Bouncer"
		send(":demo.example 001 \(nickname) :Welcome to \(name), \(nickname)")
		send(":demo.example 002 \(nickname) :Your host is demo.example")
		send(
			":demo.example 005 \(nickname) NETWORK=\(name.split(separator: " ").first.map(String.init) ?? name) "
				+ "CASEMAPPING=ascii CHANTYPES=# PREFIX=(ov)@+ CHANLIMIT=#:50 NICKLEN=30 :are supported by this server"
		)
		send(":demo.example 422 \(nickname) :MOTD File is missing")
		guard let network else { return }
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))
			for channel in network.channels where role == .bouncerAccount {
				join(channel)
			}
			try? await Task.sleep(for: .milliseconds(600))
			for line in network.directLines {
				say(line, to: nickname, from: line.sender, channelName: nickname)
			}
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
			send(":demo.example 221 \(nickname) :+i")
			return
		}
		if parts.count > 1, parts[1] == "b" || parts[1] == "+b" {
			send(":demo.example 368 \(nickname) \(target) :End of channel ban list")
		} else {
			send(":demo.example 324 \(nickname) \(target) +nt", tags: ["time": isoTimestamp(minutesAgo: 240)])
		}
	}

	private func join(_ channel: ScriptedChannel) {
		guard joined[channel.name] == nil else { return }
		joined[channel.name] = channel
		// Stamped before the first scripted line so the transcript reads in order.
		let early = ["time": isoTimestamp(minutesAgo: 240)]
		send(":\(nickname)!\(nickname)@localhost JOIN \(channel.name)", tags: early)
		send(":demo.example 332 \(nickname) \(channel.name) :\(channel.topic)", tags: early)
		let names = channel.members.map { member -> String in
			member == nickname ? member : member
		}.joined(separator: " ")
		send(":demo.example 353 \(nickname) = \(channel.name) :\(names)")
		send(":demo.example 366 \(nickname) \(channel.name) :End of NAMES list")
		Task { @MainActor in
			for line in channel.lines {
				try? await Task.sleep(for: .milliseconds(120))
				say(line, to: channel.name, from: line.sender, channelName: channel.name)
			}
		}
	}

	private func messageIdentifier(_ identifier: String, channelName: String) -> String {
		"\(role == .direct ? "d" : "b")-\(channelName.dropFirst(channelName.hasPrefix("#") ? 1 : 0))-\(identifier)"
	}

	private func say(_ line: ScriptedLine, to target: String, from sender: String, channelName: String) {
		var tags = [
			"time": isoTimestamp(minutesAgo: line.minutesAgo),
			"msgid": messageIdentifier(line.identifier, channelName: channelName),
		]
		if let replyTo = line.replyTo {
			tags["+draft/reply"] = messageIdentifier(replyTo, channelName: channelName)
		}
		let body = line.isAction ? "\u{01}ACTION \(line.text)\u{01}" : line.text
		send(":\(sender)!\(sender)@localhost PRIVMSG \(target) :\(body)", tags: tags)
	}

	func sendReactions(for channelName: String) {
		guard let channel = joined[channelName] ?? joined.values.first(where: { $0.name == channelName })
		else { return }
		for reaction in channel.reactions {
			send(
				":\(reaction.sender)!\(reaction.sender)@localhost TAGMSG \(channel.name)",
				tags: [
					"time": isoTimestamp(minutesAgo: reaction.minutesAgo),
					"+draft/react": reaction.emoji,
					"+draft/reply": messageIdentifier(reaction.target, channelName: channel.name),
				]
			)
		}
	}
}

@MainActor
final class Listener {
	let listener: NWListener
	let role: Role
	private(set) var clients: [Client] = []

	init(role: Role) throws {
		self.role = role
		let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
		parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
		listener = try NWListener(using: parameters)
	}

	func start() async throws -> UInt16 {
		listener.newConnectionHandler = { [weak self] connection in
			Task { @MainActor in
				guard let self else { return }
				let client = Client(connection: connection, role: self.role)
				client.onClose = { [weak self] closed in self?.clients.removeAll { $0 === closed } }
				self.clients.append(client)
				client.start()
			}
		}
		listener.start(queue: .global())
		while listener.state != .ready {
			try await Task.sleep(for: .milliseconds(25))
		}
		return listener.port?.rawValue ?? 0
	}

	func stop() {
		clients.forEach { $0.stop() }
		listener.cancel()
	}
}

// MARK: - Main

@MainActor
func run() async throws {
	guard CommandLine.arguments.count == 2 else {
		FileHandle.standardError.write(Data("usage: website-demo-server <state-directory>\n".utf8))
		exit(2)
	}
	let state = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
	let direct = try Listener(role: .direct)
	let bouncer = try Listener(role: .bouncerAccount)
	let directPort = try await direct.start()
	let bouncerPort = try await bouncer.start()
	try String(directPort).write(to: state.appendingPathComponent("direct-port"), atomically: true, encoding: .utf8)
	try String(bouncerPort).write(to: state.appendingPathComponent("bouncer-port"), atomically: true, encoding: .utf8)

	let control = state.appendingPathComponent("control")
	while true {
		try await Task.sleep(for: .milliseconds(250))
		guard let text = try? String(contentsOf: control, encoding: .utf8) else { continue }
		try? FileManager.default.removeItem(at: control)
		for command in text.split(separator: "\n") {
			let words = command.split(separator: " ").map(String.init)
			if words.count == 2, words[0] == "react" {
				for client in direct.clients + bouncer.clients {
					client.sendReactions(for: words[1])
				}
			}
		}
	}
}

try await run()
