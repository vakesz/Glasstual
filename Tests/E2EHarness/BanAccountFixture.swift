import Foundation

/** The server side of Ban Account.

 Registration offers `account-notify`, and the welcome's ISUPPORT announces
 `ACCOUNTEXTBAN`, so the client knows both how to write an account ban and
 which account a member is logged in to. In `#e2e` the client is an operator,
 `fixture` is logged in to `fixtureaccount` and `noaccount` is not. The one
 ban the peer accepts is `MODE #e2e +b ~account:fixtureaccount`. */
struct BanAccountFixture {
	static let member = "fixture"
	static let account = "fixtureaccount"
	static let memberWithoutAccount = "noaccount"
	static let expectedBan = "MODE #e2e +b ~account:\(account)"

	static let welcome = FixtureProtocol.welcome.map { line in
		line.contains(" 005 ")
			? ":e2e.local 005 e2euser NETWORK=E2E CASEMAPPING=rfc1459 CHANTYPES=# PREFIX=(ov)@+ "
			+ "CHANMODES=b,k,l,imnpst EXTBAN=~,a ACCOUNTEXTBAN=account :supported"
			: line
	}

	private enum Phase {
		case awaitingCapabilityList
		case negotiating
		case acknowledged
		case registered
	}

	private var phase = Phase.awaitingCapabilityList
	private var sawNick = false
	private var sawUser = false
	private(set) var joined = false
	/// The ban line the client sent, which has to be ``expectedBan``.
	private(set) var banLine: String?

	var isRegistered: Bool {
		phase == .registered
	}

	var banned: Bool {
		banLine != nil
	}

	/// Registration, until it completes.
	mutating func register(_ line: String) throws -> [String] {
		switch line {
		case "CAP LS 302", "CAP LS :302":
			guard phase == .awaitingCapabilityList else { throw Self.unexpected("capability list") }
			phase = .negotiating
			return [":e2e.local CAP * LS :account-notify"]
		case "NICK e2euser", "NICK :e2euser":
			guard phase != .awaitingCapabilityList, sawNick == false else { throw Self.unexpected("NICK") }
			sawNick = true
			return []
		case "USER e2euser 0 * :Synthetic E2E User":
			guard sawNick, sawUser == false else { throw Self.unexpected("USER") }
			sawUser = true
			return []
		case "CAP REQ :account-notify", "CAP REQ account-notify":
			guard phase == .negotiating else { throw Self.unexpected("capability request") }
			phase = .acknowledged
			return [":e2e.local CAP * ACK :account-notify"]
		case "CAP END", "CAP :END":
			guard phase == .acknowledged, sawNick, sawUser else { throw Self.unexpected("CAP END") }
			phase = .registered
			return Self.welcome
		default:
			throw Self.unexpected("registration command")
		}
	}

	/// The channel and the ban, once registered; `nil` for any other line.
	mutating func receive(_ line: String, pongSeen: Bool) throws -> [String]? {
		switch line {
		case "JOIN #e2e", "JOIN :#e2e":
			guard pongSeen, joined == false else { throw Self.unexpected("JOIN") }
			joined = true
			return [
				":e2euser!e2euser@localhost JOIN :#e2e",
				":e2e.local 353 e2euser = #e2e :@e2euser \(Self.member) \(Self.memberWithoutAccount)",
				":e2e.local 366 e2euser #e2e :End of NAMES",
				":\(Self.member)!\(Self.member)@localhost ACCOUNT \(Self.account)",
				":\(Self.member)!\(Self.member)@localhost PRIVMSG #e2e :E2E_CHANNEL_READY",
			]
		case "MODE #e2e", "MODE #e2e +b", "WHO #e2e":
			guard joined else { throw Self.unexpected("channel query") }
			return switch line {
			case "WHO #e2e": [":e2e.local 315 e2euser #e2e :End of WHO"]
			case "MODE #e2e +b": [":e2e.local 368 e2euser #e2e :End of bans"]
			default: [":e2e.local 324 e2euser #e2e +nt"]
			}
		case let line where line.hasPrefix("MODE #e2e +b "):
			guard joined, banLine == nil, line == Self.expectedBan else {
				throw HarnessFailure.assertion("Ban Account sent an unexpected ban; payload withheld")
			}
			banLine = line
			return [":e2euser!e2euser@localhost \(line)"]
		default:
			return nil
		}
	}

	private static func unexpected(_ what: String) -> HarnessFailure {
		.assertion("Unexpected \(what) in the Ban Account exchange; payload withheld")
	}
}
