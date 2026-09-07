import Foundation

enum ScenarioKind: String, CaseIterable {
	case rejectionRetry
	case repeatedRejection
	case channelMessaging
	case channelDenied
	case historyRelaunch
	case settingsSnapshot
	case onboardingSkip
	case onboardingFinish
	case pluginSmiley
	case dccSuccess
	case dccCancel
	case burstResponsiveness
	case tlsAccept
	case tlsRejectRetry
	case tlsStall

	var rejectionCount: Int {
		switch self {
		case .rejectionRetry: 1
		case .repeatedRejection: 3
		default: 0
		}
	}

	var secured: Bool {
		[.tlsAccept, .tlsRejectRetry, .tlsStall].contains(self)
	}

	var connectedQuit: Bool {
		![.rejectionRetry, .tlsStall, .settingsSnapshot].contains(self)
	}

	var messaging: Bool {
		self == .channelMessaging || self == .historyRelaunch
	}

	var finalChannel: String? {
		self == .channelDenied ? "#retry" : (usesChannel ? "#e2e" : nil)
	}

	var hasFixtureTest: Bool {
		self != .settingsSnapshot && self != .onboardingSkip
	}

	var onboarding: Bool {
		self == .onboardingSkip || self == .onboardingFinish
	}

	var dcc: Bool {
		self == .dccSuccess || self == .dccCancel
	}

	var interactive: Bool {
		[.pluginSmiley, .dccSuccess, .dccCancel, .burstResponsiveness].contains(self)
	}

	var usesChannel: Bool {
		messaging || self == .pluginSmiley || self == .burstResponsiveness
	}

	/// The single list of modes `make e2e-fixtures` runs; the script asks the
	/// helper for it rather than repeating the names.
	static var fixtureModes: [String] {
		allCases.filter(\.hasFixtureTest).map(\.rawValue)
	}

	static var current: Self {
		get throws {
			guard let kind = try Self(rawValue: HarnessFiles.required("E2E_SCENARIO")) else {
				throw HarnessFailure.setup("Unknown scenario")
			}
			return kind
		}
	}
}

/// Only synthetic values enter evidence. Unexpected wire content is never printed.
struct FixtureProtocol {
	static let registration = [
		["CAP LS 302", "CAP LS :302"], ["NICK e2euser", "NICK :e2euser"],
		["USER e2euser 0 * :Synthetic E2E User"], ["CAP END", "CAP :END"],
	]
	var registrationIndex = 0
	var pongSeen = false
	var quitSeen = false
	var joined = false
	var messageSeen = false
	var replySeen = false
	let reject: Bool
	let messaging: Bool
	var deniedJoin: DeniedJoinFixture?
	var interaction: InteractiveFixture?

	mutating func receive(_ line: String) throws -> [String] {
		guard !quitSeen else { throw HarnessFailure.assertion("Command after QUIT; payload withheld") }
		if registrationIndex < Self.registration.count {
			return try register(line)
		}
		return try command(line)
	}

	private mutating func register(_ line: String) throws -> [String] {
		guard Self.registration[registrationIndex].contains(line) else {
			throw HarnessFailure.assertion("Registration order or arguments mismatch; payload withheld")
		}
		registrationIndex += 1
		if registrationIndex == 1 {
			return [":e2e.local CAP * LS :"]
		}
		if registrationIndex == Self.registration.count {
			if reject {
				return ["ERROR :E2E_REGISTRATION_REJECTED"]
			}
			return [
				":e2e.local 001 e2euser :Welcome to E2E",
				":e2e.local 005 e2euser NETWORK=E2E CASEMAPPING=rfc1459 CHANTYPES=# :supported",
				":e2e.local 422 e2euser :No MOTD", "PING :E2E_PING",
				":e2e.local NOTICE e2euser :E2E_TRANSCRIPT_READY",
			]
		}
		return []
	}

	/// The sub-fixture owns its phase: write it back on every path, so a line it
	/// declines or rejects cannot silently discard a state change it just made.
	private mutating func subFixture(_ line: String) throws -> [String]? {
		if var interaction {
			defer { self.interaction = interaction }
			if let response = try interaction.receive(line, joined: joined) {
				return response
			}
		}
		if var deniedJoin {
			defer { self.deniedJoin = deniedJoin }
			if let response = try deniedJoin.receive(line, pongSeen: pongSeen) {
				return response
			}
		}
		return nil
	}

	private mutating func command(_ line: String) throws -> [String] {
		if let response = try subFixture(line) {
			return response
		}
		switch line {
		case "PONG E2E_PING", "PONG :E2E_PING":
			guard !pongSeen else { throw HarnessFailure.assertion("Duplicate PONG") }
			pongSeen = true
		case "MODE e2euser", "MODE :e2euser":
			let modes = deniedJoin?.phase == .identified || deniedJoin?.phase == .joined ? "+r" : "+"
			return [":e2e.local 221 e2euser :\(modes)"]
		case "JOIN #e2e", "JOIN :#e2e":
			guard messaging || interaction?.kind.usesChannel == true, pongSeen,
			      !joined else { throw HarnessFailure.assertion("Unexpected JOIN") }
			joined = true
			return [
				":e2euser!e2euser@localhost JOIN :#e2e",
				":e2e.local 353 e2euser = #e2e :e2euser fixture",
				":e2e.local 366 e2euser #e2e :End of NAMES",
				":fixture!fixture@localhost PRIVMSG #e2e :E2E_CHANNEL_READY",
			]
		case "MODE #e2e", "MODE #e2e +b", "WHO #e2e":
			guard joined else { throw HarnessFailure.assertion("Channel query before JOIN") }
			if line == "WHO #e2e" {
				return [":e2e.local 315 e2euser #e2e :End of WHO"]
			}
			if line == "MODE #e2e +b" {
				return [":e2e.local 368 e2euser #e2e :End of bans"]
			}
			return [":e2e.local 324 e2euser #e2e +nt"]
		case "PRIVMSG #e2e :E2E_TYPED_MESSAGE":
			guard joined, !messageSeen else { throw HarnessFailure.assertion("Unexpected typed message") }
			messageSeen = true
			return [":fixture!fixture@localhost PRIVMSG #e2e :E2E_SERVER_REPLY"]
		case "PRIVMSG #e2e :fixture: E2E_TYPED_REPLY":
			guard messageSeen, !replySeen else { throw HarnessFailure.assertion("Unexpected typed reply") }
			replySeen = true
			return [":fixture!fixture@localhost PRIVMSG #e2e :E2E_REPLY_ACK"]
		case "QUIT E2E_QUIT", "QUIT :E2E_QUIT":
			guard pongSeen, !messaging || replySeen else { throw HarnessFailure.assertion("Premature QUIT") }
			guard deniedJoin == nil || deniedJoin?.phase == .joined else {
				throw HarnessFailure.assertion("QUIT before denied-channel recovery")
			}
			guard interaction == nil || interaction?.finished == true
			else { throw HarnessFailure.assertion("QUIT before fixture interaction completed") }
			quitSeen = true
		default:
			throw HarnessFailure.assertion("Unexpected command or arguments; payload withheld")
		}
		return []
	}

	func eof(pending: Data) throws {
		guard quitSeen, pending.isEmpty else { throw HarnessFailure.assertion("Unexpected client EOF") }
	}
}

struct DeniedJoinFixture {
	enum Phase { case initial, otherJoined, denied, identified, joined }
	var phase = Phase.initial

	mutating func receive(_ line: String, pongSeen: Bool) throws -> [String]? {
		switch line {
		case "JOIN #other", "JOIN :#other":
			guard pongSeen,
			      phase == .initial else { throw HarnessFailure.assertion("Wrong-target or duplicate JOIN #other") }
			phase = .otherJoined
			return Self.joined("#other", marker: "E2E_OTHER_READY")
		case "JOIN #retry", "JOIN :#retry":
			if phase == .otherJoined {
				phase = .denied
				return [":e2e.local 477 e2euser #retry :E2E_JOIN_DENIED Identify with NickServ first"]
			}
			guard phase == .identified
			else { throw HarnessFailure.assertion("Retry JOIN before identification or duplicate retry") }
			phase = .joined
			return Self.joined("#retry", marker: "E2E_RETRY_JOINED")
		case "PRIVMSG NickServ :IDENTIFY E2E_SYNTHETIC":
			guard phase == .denied else { throw HarnessFailure.assertion("Identification before denied JOIN") }
			phase = .identified
			return [
				":e2e.local 900 e2euser e2euser!e2euser@localhost e2eaccount :You are now logged in as e2eaccount",
				":e2euser!e2euser@localhost ACCOUNT e2eaccount",
				":e2e.local MODE e2euser :+r",
				":NickServ!service@services.e2e.local NOTICE e2euser :You are now identified for e2euser.",
				":fixture!fixture@localhost PRIVMSG #other :E2E_IDENTIFIED_READY",
			]
		case "MODE #other", "MODE #other +b", "WHO #other", "MODE #retry", "MODE #retry +b", "WHO #retry":
			let channel = line.contains("#other") ? "#other" : "#retry"
			guard channel == "#other" ? phase != .initial : phase == .joined else {
				throw HarnessFailure.assertion("Query for channel not joined")
			}
			if line.hasPrefix("WHO ") {
				return [":e2e.local 315 e2euser \(channel) :End of WHO"]
			}
			if line.hasSuffix(" +b") {
				return [":e2e.local 368 e2euser \(channel) :End of bans"]
			}
			return [":e2e.local 324 e2euser \(channel) +nt"]
		default: return nil
		}
	}

	private static func joined(_ channel: String, marker: String) -> [String] {
		[":e2euser!e2euser@localhost JOIN :\(channel)",
		 ":e2e.local 353 e2euser = \(channel) :e2euser fixture",
		 ":e2e.local 366 e2euser \(channel) :End of NAMES",
		 ":fixture!fixture@localhost PRIVMSG \(channel) :\(marker)"]
	}
}
