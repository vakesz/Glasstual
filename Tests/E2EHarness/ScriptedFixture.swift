import Foundation

/** A server behaviour that owns registration and then answers its own
 commands: the IRCv3 extensions a scenario exercises.

 ``FixtureProtocol`` hands it every line until it reports itself registered,
 then every line it does not decline with `nil`. `PONG`, `ISON`, the user's
 own `MODE` and `QUIT` stay with ``FixtureProtocol``. */
protocol ScriptedFixture {
	var registration: CapabilityRegistration { get set }
	/// A line before registration completes. The default is the standard lines.
	mutating func register(_ line: String) throws -> [String]
	/// A line after registration, or `nil` when it is not this fixture's.
	mutating func receive(_ line: ClientLine, pongSeen: Bool) throws -> [String]?
	/// Whether everything the scenario exercises has happened, so `QUIT` is due.
	var finished: Bool { get }
	/// What the scenario checks, with no payload in it.
	var evidence: String { get }
}

extension ScriptedFixture {
	mutating func register(_ line: String) throws -> [String] {
		try registration.receive(line)
	}
}

/// One line from the client, with its message tags taken off the front.
struct ClientLine {
	let tags: [String: String]
	/// The line without its tags.
	let text: String

	init(_ line: String) {
		guard line.hasPrefix("@"), let space = line.firstIndex(of: " ") else {
			tags = [:]
			text = line
			return
		}
		var tags: [String: String] = [:]
		for tag in line[line.index(after: line.startIndex) ..< space].split(separator: ";") {
			let parts = tag.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			tags[String(parts[0])] = parts.count == 2 ? String(parts[1]) : ""
		}
		self.tags = tags
		text = String(line[line.index(after: space)...])
	}

	/// A typing notification, which the client sends while its user edits a
	/// message wherever `message-tags` is on. No scenario is about it.
	var isTypingNotification: Bool {
		text.hasPrefix("TAGMSG ") && tags.keys.allSatisfy { $0 == "+typing" || $0 == "+draft/typing" }
	}
}

/** Registration with capability negotiation: `CAP LS`, `NICK`, `USER`, any
 number of `CAP REQ` for capabilities that were offered, then `CAP END`.

 The client asks for a capability's dependencies before the capability, so the
 requests arrive in several lines; each is acknowledged whole. Asking for
 anything that was not offered, or out of order, is a violation. */
struct CapabilityRegistration {
	/// The `CAP LS` value: names, with values where the capability has them.
	let offer: [String]
	/// The capabilities the client must have asked for by `CAP END`.
	let required: Set<String>
	/// ISUPPORT tokens beyond the shared ones.
	let support: String

	private var listed = false
	private var sawNick = false
	private var sawUser = false
	private(set) var acknowledged: Set<String> = []
	private(set) var isRegistered = false

	init(offer: [String], required: Set<String>? = nil, support: String = "") {
		self.offer = offer
		let names = Set(offer.map(Self.name))
		self.required = required ?? names
		self.support = support
	}

	private static func name(_ capability: String) -> String {
		String(capability.split(separator: "=", maxSplits: 1)[0])
	}

	var welcome: [String] {
		FixtureProtocol.welcome.map { line in
			line.contains(" 005 ") && support.isEmpty == false
				? ":e2e.local 005 e2euser NETWORK=E2E CASEMAPPING=rfc1459 CHANTYPES=# \(support) :supported"
				: line
		}
	}

	/// A registration line. `extra` answers what the fixture allows before
	/// `CAP END` beyond the standard lines, such as `AUTHENTICATE`.
	mutating func receive(_ line: String, extra: (String) throws -> [String]? = { _ in nil }) throws -> [String] {
		switch line {
		case "CAP LS 302", "CAP LS :302":
			guard listed == false else { throw Self.unexpected("capability list") }
			listed = true
			return [":e2e.local CAP * LS :" + offer.joined(separator: " ")]
		case "NICK e2euser", "NICK :e2euser":
			guard listed, sawNick == false else { throw Self.unexpected("NICK") }
			sawNick = true
			return []
		case "USER e2euser 0 * :Synthetic E2E User":
			guard sawNick, sawUser == false else { throw Self.unexpected("USER") }
			sawUser = true
			return []
		case "CAP END", "CAP :END":
			guard sawNick, sawUser, required.isSubset(of: acknowledged) else { throw Self.unexpected("CAP END") }
			isRegistered = true
			return welcome
		default:
			if let names = Self.requested(in: line) {
				return try acknowledge(names)
			}
			if let response = try extra(line) {
				return response
			}
			throw Self.unexpected("registration command")
		}
	}

	/// A `CAP REQ` after registration, such as the `sasl` a re-authentication
	/// asks for, or `nil` when `line` is not one.
	mutating func receiveLateRequest(_ line: String) throws -> [String]? {
		guard let names = Self.requested(in: line) else { return nil }
		return try acknowledge(names)
	}

	private static func requested(in line: String) -> [String]? {
		guard line.hasPrefix("CAP REQ ") else { return nil }
		var names = line.dropFirst("CAP REQ ".count)
		if names.hasPrefix(":") {
			names = names.dropFirst()
		}
		return names.split(separator: " ").map(String.init)
	}

	private mutating func acknowledge(_ names: [String]) throws -> [String] {
		let offered = Set(offer.map(Self.name))
		guard listed, names.isEmpty == false, names.allSatisfy(offered.contains),
		      acknowledged.isDisjoint(with: names)
		else { throw Self.unexpected("capability request") }
		acknowledged.formUnion(names)
		return [":e2e.local CAP e2euser ACK :" + names.joined(separator: " ")]
	}

	private static func unexpected(_ what: String) -> HarnessFailure {
		.assertion("Unexpected \(what) during capability registration; payload withheld")
	}
}

/// The channel every scripted fixture joins its client to, and the queries a
/// client makes of a channel it joined.
struct ScriptedChannel {
	static let name = "#e2e"
	private(set) var joined = false
	private(set) var joins = 0

	/// `JOIN`, `PART` and the channel queries; `nil` for any other line.
	/// `burst` is what follows the names on a join.
	mutating func receive(_ line: String, pongSeen: Bool, members: String = "e2euser fixture", burst: [String]) throws -> [String]? {
		switch line {
		case "JOIN #e2e", "JOIN :#e2e":
			guard pongSeen, joined == false else { throw HarnessFailure.assertion("Unexpected JOIN") }
			joined = true
			joins += 1
			return [
				":e2euser!e2euser@localhost JOIN :#e2e",
				":e2e.local 353 e2euser = #e2e :\(members)",
				":e2e.local 366 e2euser #e2e :End of NAMES",
			] + burst
		case "MODE #e2e", "MODE #e2e +b", "WHO #e2e":
			guard joined else { throw HarnessFailure.assertion("Channel query before JOIN") }
			return switch line {
			case "WHO #e2e": [":e2e.local 315 e2euser #e2e :End of WHO"]
			case "MODE #e2e +b": [":e2e.local 368 e2euser #e2e :End of bans"]
			default: [":e2e.local 324 e2euser #e2e +nt"]
			}
		default:
			if line == "PART #e2e" || line.hasPrefix("PART #e2e :") {
				guard joined else { throw HarnessFailure.assertion("PART before JOIN") }
				joined = false
				return [":e2euser!e2euser@localhost PART #e2e"]
			}
			return nil
		}
	}
}
