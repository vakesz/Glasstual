import Foundation

/** What the loopback peer plays. Each mode is one server behaviour a GUI
 scenario drives the application against, and one synthetic-client self-test
 `glasstual-e2e fixtures` runs without the application. */
enum FixtureMode: String, CaseIterable {
	/// Registers, answers PING, and takes QUIT; nothing else.
	case registration
	case rejectionRetry
	case repeatedRejection
	case channelMessaging
	case channelDenied
	case historyRelaunch
	case onboardingFinish
	case dccSuccess
	case dccCancel
	case burstResponsiveness
	case tlsAccept
	case tlsRejectRetry
	case tlsStall
	case credentialConsentDecline
	case credentialConsentSend
	case banAccount
	/// `channelMessaging` carried over `ws://`, and over `wss://`.
	case webSocketMessaging
	case webSocketSecure
	/// A `DCC SSEND` from a peer never seen, and from one whose certificate changed.
	case dccSecure
	case dccSecureChanged
	/// A passive `DCC SCHAT` from a peer never seen: a line each way over TLS.
	case dccSecureChat
	case xdccRequest
	case accountRegistration
	case metadataEdit
	case saslSignInAgain
	case replyPrivately
	case historyGapBanner
	case showOriginalMessage

	var rejectionCount: Int {
		switch self {
		case .rejectionRetry: 1
		case .repeatedRejection: 3
		default: 0
		}
	}

	var secured: Bool {
		[.tlsAccept, .tlsRejectRetry, .tlsStall, .credentialConsentDecline, .credentialConsentSend, .webSocketSecure]
			.contains(self)
	}

	/// Whether IRC lines travel in WebSocket text messages.
	var webSocket: Bool {
		self == .webSocketMessaging || self == .webSocketSecure
	}

	var messaging: Bool {
		self == .channelMessaging || self == .historyRelaunch || webSocket
	}

	/// What the user answers when the client asks whether to send its
	/// passwords to a server whose certificate it did not check; `nil` for
	/// every other mode. These run over TLS with chain validation off.
	var saslConsent: SASLConsentFixture.Answer? {
		switch self {
		case .credentialConsentDecline: .decline
		case .credentialConsentSend: .send
		default: nil
		}
	}

	var dcc: Bool {
		[.dccSuccess, .dccCancel, .dccSecure, .dccSecureChanged, .dccSecureChat, .xdccRequest].contains(self)
	}

	/// Whether the DCC peer speaks TLS, as a `DCC SSEND` or `DCC SCHAT` asks.
	var secureDCC: Bool {
		self == .dccSecure || self == .dccSecureChanged || self == .dccSecureChat
	}

	/// Whether the DCC peer offers a chat rather than a file.
	var directChat: Bool {
		self == .dccSecureChat
	}

	/// How many files the DCC peer offers, one after another.
	var dccTransfers: Int {
		self == .dccSecureChanged ? 2 : 1
	}

	var interactive: Bool {
		dcc || self == .burstResponsiveness
	}

	/// The fixture that owns registration and the extension this mode exercises.
	var scripted: (any ScriptedFixture)? {
		switch self {
		case .accountRegistration: AccountRegistrationFixture()
		case .metadataEdit: MetadataFixture()
		case .saslSignInAgain: SASLSignInFixture()
		case .replyPrivately: PrivateReplyFixture()
		case .historyGapBanner: HistoryFixture(.gap)
		case .showOriginalMessage: HistoryFixture(.originalMessage)
		default: nil
		}
	}

	var usesChannel: Bool {
		messaging || self == .burstResponsiveness || self == .banAccount
	}
}

/// Only synthetic values enter evidence. Unexpected wire content is never printed.
struct FixtureProtocol {
	private static let e2eQuitLines: Set<String> = ["QUIT E2E_QUIT", "QUIT :E2E_QUIT"]
	private static let onboardingQuitLines: Set<String> = [
		"QUIT :Glasstual IRC Client: https://github.com/vakesz/Glasstual",
	]

	/// What the server says once registration completes, shared by every scenario.
	static let welcome = [
		":e2e.local 001 e2euser :Welcome to E2E",
		":e2e.local 005 e2euser NETWORK=E2E CASEMAPPING=rfc1459 CHANTYPES=# :supported",
		":e2e.local 422 e2euser :No MOTD", "PING :E2E_PING",
		":e2e.local NOTICE e2euser :E2E_TRANSCRIPT_READY",
	]

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
	let acceptsOnboardingQuit: Bool
	/// Owns registration until it completes, for the credential-consent scenarios.
	var consent: SASLConsentFixture?
	/// Owns registration, the channel and the ban, for Ban Account.
	var banAccount: BanAccountFixture?
	/// Owns registration and its extension's commands, for the scripted modes.
	var scripted: (any ScriptedFixture)?

	init(
		reject: Bool,
		messaging: Bool,
		deniedJoin: DeniedJoinFixture? = nil,
		interaction: InteractiveFixture? = nil,
		acceptsOnboardingQuit: Bool = false,
		consent: SASLConsentFixture? = nil,
		banAccount: BanAccountFixture? = nil,
		scripted: (any ScriptedFixture)? = nil
	) {
		self.reject = reject
		self.messaging = messaging
		self.deniedJoin = deniedJoin
		self.interaction = interaction
		self.acceptsOnboardingQuit = acceptsOnboardingQuit
		self.consent = consent
		self.banAccount = banAccount
		self.scripted = scripted
	}

	/// The peer for `mode`, on connection attempt `attempt` (from 1).
	init(mode: FixtureMode, attempt: Int, interaction: InteractiveFixture? = nil) {
		self.init(
			reject: attempt <= mode.rejectionCount,
			messaging: mode.messaging,
			deniedJoin: mode == .channelDenied ? DeniedJoinFixture() : nil,
			interaction: interaction,
			acceptsOnboardingQuit: mode == .onboardingFinish,
			consent: mode.saslConsent.map(SASLConsentFixture.init(answer:)),
			banAccount: mode == .banAccount ? BanAccountFixture() : nil,
			scripted: mode.scripted
		)
	}

	mutating func receive(_ line: String) throws -> [String] {
		guard !quitSeen else { throw HarnessFailure.assertion("Command after QUIT; payload withheld") }
		if var banAccount, !banAccount.isRegistered {
			defer {
				self.banAccount = banAccount
				if banAccount.isRegistered {
					registrationIndex = Self.registration.count
				}
			}
			return try banAccount.register(line)
		}
		if var scripted, !scripted.registration.isRegistered {
			defer {
				self.scripted = scripted
				if scripted.registration.isRegistered {
					registrationIndex = Self.registration.count
				}
			}
			return try scripted.register(line)
		}
		if var consent, !consent.isRegistered {
			defer {
				self.consent = consent
				// The consent exchange stood in for the ordinary registration lines.
				if consent.isRegistered {
					registrationIndex = Self.registration.count
				}
			}
			return try consent.receive(line)
		}
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
			return Self.welcome
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
		if var banAccount {
			defer { self.banAccount = banAccount }
			if let response = try banAccount.receive(line, pongSeen: pongSeen) {
				return response
			}
		}
		if var scripted {
			defer { self.scripted = scripted }
			let client = ClientLine(line)
			if client.isTypingNotification {
				return []
			}
			if let response = try scripted.receive(client, pongSeen: pongSeen) {
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
		case let line where line.hasPrefix("ISON ") && line.split(separator: " ").count == 2:
			// Queries ask whether their nickname is online; it is.
			return [":e2e.local 303 e2euser :\(line.dropFirst("ISON ".count))"]
		case "MODE e2euser", "MODE :e2euser":
			let modes = deniedJoin?.phase == .identified || deniedJoin?.phase == .joined ? "+r" : "+"
			return [":e2e.local 221 e2euser :\(modes)"]
		case "JOIN #e2e", "JOIN :#e2e":
			guard messaging || interaction?.mode.usesChannel == true, pongSeen,
			      !joined else { throw HarnessFailure.assertion("Unexpected JOIN") }
			joined = true
			/* The burst is this JOIN's NAMES reply: its last batch lists the
			 two of us and ends the list. A client ignores names that arrive
			 after the end of the list it joined with. */
			let names = interaction?.mode == .burstResponsiveness ? [] : [
				":e2e.local 353 e2euser = #e2e :e2euser fixture",
				":e2e.local 366 e2euser #e2e :End of NAMES",
			]
			return [":e2euser!e2euser@localhost JOIN :#e2e"] + names
				+ [":fixture!fixture@localhost PRIVMSG #e2e :E2E_CHANNEL_READY"]
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
		case let line where Self.e2eQuitLines.contains(line) ||
			(acceptsOnboardingQuit && Self.onboardingQuitLines.contains(line)):
			try requireReadyToQuit()
			quitSeen = true
		default:
			throw HarnessFailure.assertion("Unexpected \(Self.redactedShape(of: line)); payload withheld")
		}
		return []
	}

	/// QUIT is accepted only once everything the mode exercises has happened.
	private func requireReadyToQuit() throws {
		guard pongSeen, !messaging || replySeen else { throw HarnessFailure.assertion("Premature QUIT") }
		guard deniedJoin == nil || deniedJoin?.phase == .joined else {
			throw HarnessFailure.assertion("QUIT before denied-channel recovery")
		}
		guard interaction == nil || interaction?.finished == true
		else { throw HarnessFailure.assertion("QUIT before fixture interaction completed") }
		guard banAccount == nil || banAccount?.banned == true
		else { throw HarnessFailure.assertion("QUIT before the account ban") }
		guard scripted == nil || scripted?.finished == true
		else { throw HarnessFailure.assertion("QUIT before the scripted exchange completed") }
	}

	private static func redactedShape(of line: String) -> String {
		let fields = line.split(separator: " ", omittingEmptySubsequences: true)
		let command = fields.first.map(String.init) ?? "empty command"
		let parameterCount = max(fields.count - 1, 0)
		let hasTrailingParameter = line.contains(" :")
		let ctcpCommand: String
		if let start = line.firstIndex(of: "\u{01}") {
			let payload = line[line.index(after: start)...]
			ctcpCommand = payload.split(separator: " ").prefix(2).joined(separator: " ")
		} else {
			ctcpCommand = "none"
		}
		return "command shape (verb \(command), parameters \(parameterCount), trailing \(hasTrailingParameter), CTCP \(ctcpCommand))"
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
