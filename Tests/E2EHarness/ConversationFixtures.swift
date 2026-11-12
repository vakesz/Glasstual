import Foundation

/** The server side of Reply Privately: `message-tags`, so a private message
 can say which channel it belongs to.

 The channel holds one message from `fixture` with a message identifier. The
 one private message this fixture accepts goes to `fixture`, carries
 `+draft/channel-context` naming the channel and `+draft/reply` naming that
 message, and is answered the same way, so the answer is filed in the channel. */
struct PrivateReplyFixture: ScriptedFixture {
	static let originalIdentifier = "e2e-original"
	static let original = "E2E_ORIGINAL_MESSAGE"
	static let reply = "E2E_PRIVATE_REPLY"
	static let acknowledgement = "E2E_PRIVATE_ACK"

	var registration = CapabilityRegistration(offer: ["message-tags"])
	private var channel = ScriptedChannel()
	private(set) var replied = false

	var finished: Bool {
		replied
	}

	var evidence: String {
		"replied=\(replied)"
	}

	static let expectedEvidence = "replied=true"

	mutating func receive(_ line: ClientLine, pongSeen: Bool) throws -> [String]? {
		if let response = try channel.receive(line.text, pongSeen: pongSeen, burst: [
			"@msgid=\(Self.originalIdentifier) :fixture!fixture@localhost PRIVMSG #e2e :\(Self.original)",
		]) {
			return response
		}
		guard line.text.hasPrefix("PRIVMSG fixture ") else { return nil }
		guard channel.joined, replied == false, line.text == "PRIVMSG fixture :\(Self.reply)",
		      line.tags["+draft/channel-context"] == ScriptedChannel.name,
		      line.tags["+draft/reply"] == Self.originalIdentifier
		else { throw HarnessFailure.assertion("The reply did not carry its channel context and the message it answers; payload withheld") }
		replied = true
		return [
			"@+draft/channel-context=#e2e;msgid=e2e-private-ack :fixture!fixture@localhost PRIVMSG e2euser :\(Self.acknowledgement)",
		]
	}
}

/** The server side of `draft/chathistory`, for the missing-messages banner and
 for Show Original Message.

 It keeps a list of synthetic messages a minute apart and serves `LATEST`,
 `AFTER`, `BEFORE`, `BETWEEN` and `AROUND` over it by message identifier or
 timestamp, each page in a `chathistory` batch.

 - `gap`: pages hold two lines. The channel has two messages when it is first
 joined and thirty once the client has left it, so a catch-up on rejoining
 pages forward ten times, fetches the live end and leaves six messages
 between. Loading them asks for what lies `BETWEEN`.
 - `originalMessage`: the live end is one message that replies to another the
 client has never seen, which `AROUND` then returns with its neighbours. */
struct HistoryFixture: ScriptedFixture {
	enum Script {
		case gap
		case originalMessage
	}

	struct Entry {
		let identifier: String
		let time: Date
		let text: String
		var replyTo: String?
	}

	/// The messages a rejoining client cannot reach by paging forward.
	static let gapMarkers = (22 ... 27).map { "E2E_HISTORY_\($0)_" }
	static let liveEndMarker = "E2E_HISTORY_29_"
	static let firstMarker = "E2E_HISTORY_1_"
	static let replyMarker = "E2E_REPLY_MESSAGE"
	static let originalMarker = "E2E_ORIGINAL_MESSAGE"
	static let originalIdentifier = "e2e-original"

	let script: Script
	var registration: CapabilityRegistration
	private var channel = ScriptedChannel()
	private var entries: [Entry]
	private let origin = Date(timeIntervalSinceNow: -7200)
	private var batches = 0
	/// The identifiers served so far, in any page.
	private(set) var served: Set<String> = []
	private(set) var betweenRequests = 0
	private(set) var aroundRequests = 0

	init(_ script: Script) {
		self.script = script
		registration = CapabilityRegistration(
			offer: ["batch", "server-time", "message-tags", "draft/chathistory"],
			support: "CHATHISTORY=\(script == .gap ? 2 : 50) MSGREFTYPES=msgid,timestamp"
		)
		entries = []
		switch script {
		case .gap:
			entries = (0 ..< 2).map(entry)
		case .originalMessage:
			entries = [
				Entry(identifier: "e2e-before", time: origin, text: "E2E_CONTEXT_BEFORE"),
				Entry(identifier: Self.originalIdentifier, time: origin + 60, text: Self.originalMarker),
				Entry(identifier: "e2e-after", time: origin + 120, text: "E2E_CONTEXT_AFTER"),
			] + (0 ..< 60).map { Entry(identifier: "e2e-filler-\($0)", time: origin + 180 + Double($0) * 60, text: "E2E_FILLER_\($0)_") }
				+ [Entry(identifier: "e2e-reply", time: origin + 3900, text: Self.replyMarker, replyTo: Self.originalIdentifier)]
		}
	}

	private func entry(_ index: Int) -> Entry {
		Entry(identifier: "e2e-\(index)", time: origin + Double(index) * 60, text: "E2E_HISTORY_\(index)_")
	}

	var finished: Bool {
		switch script {
		case .gap: served.count == 30 && betweenRequests > 0
		case .originalMessage: aroundRequests == 1 && served.contains(Self.originalIdentifier)
		}
	}

	var evidence: String {
		"served=\(served.count) between=\(betweenRequests) around=\(aroundRequests)"
	}

	mutating func receive(_ line: ClientLine, pongSeen: Bool) throws -> [String]? {
		let wasJoined = channel.joined
		if let response = try channel.receive(line.text, pongSeen: pongSeen, burst: []) {
			if script == .gap, wasJoined, channel.joined == false, entries.count == 2 {
				// The channel went on while the client was away.
				entries += (2 ..< 30).map(entry)
			}
			return response
		}
		guard line.text.hasPrefix("CHATHISTORY ") else { return nil }
		let fields = line.text.split(separator: " ").map(String.init)
		guard fields.count >= 4 else { throw Self.unexpected("command") }
		if fields[1] == "TARGETS" {
			batches += 1
			let reference = "e2etargets\(batches)"
			return Self.labelled(line, [":e2e.local BATCH +\(reference) draft/chathistory-targets", ":e2e.local BATCH -\(reference)"])
		}
		guard fields[2] == ScriptedChannel.name, channel.joined, let limit = Int(fields.last ?? ""), limit > 0 else {
			throw Self.unexpected("target or limit")
		}
		let page: [Entry]
		switch (fields[1], fields.count) {
		case ("LATEST", 5):
			let lower = fields[3] == "*" ? -1 : try index(of: fields[3], roundingUp: false)
			page = Array(entries[(lower + 1)...].suffix(limit))
		case ("AFTER", 5):
			page = try Array(entries[(index(of: fields[3], roundingUp: false) + 1)...].prefix(limit))
		case ("BEFORE", 5):
			page = try Array(entries[..<index(of: fields[3], roundingUp: true)].suffix(limit))
		case ("BETWEEN", 6):
			let lower = try index(of: fields[3], roundingUp: false)
			let upper = try index(of: fields[4], roundingUp: true)
			guard script == .gap, lower < upper else { throw Self.unexpected("BETWEEN range") }
			betweenRequests += 1
			page = Array(entries[(lower + 1) ..< upper].prefix(limit))
		case ("AROUND", 5):
			guard script == .originalMessage, fields[3] == "msgid=" + Self.originalIdentifier else {
				throw Self.unexpected("AROUND reference")
			}
			aroundRequests += 1
			page = Array(entries.prefix(3))
		default:
			throw Self.unexpected("subcommand")
		}
		served.formUnion(page.map(\.identifier))
		batches += 1
		let reference = "e2ehistory\(batches)"
		return Self.labelled(line, [":e2e.local BATCH +\(reference) chathistory \(ScriptedChannel.name)"]
			+ page.map { Self.line($0, batch: reference) } + [":e2e.local BATCH -\(reference)"])
	}

	/// A labelled request is answered under its label, on the batch that opens the answer.
	private static func labelled(_ request: ClientLine, _ lines: [String]) -> [String] {
		guard let label = request.tags["label"], let first = lines.first else { return lines }
		return ["@label=\(label) " + first] + lines.dropFirst()
	}

	/// The position a reference names. A timestamp between two messages
	/// resolves to the one before it, or with `roundingUp` the one after.
	private func index(of reference: String, roundingUp: Bool) throws -> Int {
		if reference.hasPrefix("msgid=") {
			let identifier = reference.dropFirst("msgid=".count)
			guard let index = entries.firstIndex(where: { $0.identifier == identifier }) else {
				throw Self.unexpected("message reference")
			}
			return index
		}
		guard reference.hasPrefix("timestamp="),
		      let date = try? Date(String(reference.dropFirst("timestamp=".count)), strategy: Self.timestamp)
		else { throw Self.unexpected("reference") }
		if roundingUp {
			return entries.firstIndex { $0.time >= date } ?? entries.count
		}
		return (entries.lastIndex { $0.time <= date }) ?? -1
	}

	private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

	private static func line(_ entry: Entry, batch: String) -> String {
		var tags = ["batch=\(batch)", "time=\(entry.time.formatted(timestamp))", "msgid=\(entry.identifier)"]
		if let replyTo = entry.replyTo {
			tags.append("+draft/reply=\(replyTo)")
		}
		return "@\(tags.joined(separator: ";")) :fixture!fixture@localhost PRIVMSG \(ScriptedChannel.name) :\(entry.text)"
	}

	private static func unexpected(_ what: String) -> HarnessFailure {
		.assertion("Unexpected CHATHISTORY \(what); payload withheld")
	}
}
