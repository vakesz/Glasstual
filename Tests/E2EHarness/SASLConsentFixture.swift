import Foundation

/** The server side of the credential-consent prompt.

 The client has a server password and a SASL password and does not validate
 the certificate, so before anything that would carry a password goes out it
 asks its user (`ServerSession+RegistrationGate.swift`). Nothing is sent before
 the answer, not even `CAP LS`: the GUI scenario checks that the peer has
 received no line while the question is on screen, and this fixture checks the
 order and content of what follows.

 - Send Password: `CAP LS`, `PASS` with the server secret, `NICK`, `USER`, then
 SASL `PLAIN` with the account secret, then `CAP END`.
 - Don't Send: `CAP LS`, `NICK`, `USER` and `CAP END`; no `PASS` and no SASL.

 It owns registration for these modes, because the fixed list in
 `FixtureProtocol.registration` has no room for either. The secrets are
 synthetic and no line, payload or failure message is ever printed; a failure
 names the shape of what went wrong and nothing it carried. */
struct SASLConsentFixture {
	/// What the user is expected to answer when the client asks.
	enum Answer {
		case decline
		case send
	}

	/// Not credentials for anything. The harness types them into the client's
	/// Server Properties and this fixture looks for them on the wire.
	static let secret = "E2E_SASL_SYNTHETIC_SECRET"
	static let serverSecret = "E2E_SERVER_SYNTHETIC_SECRET"
	static let account = "e2euser"

	/// What `AUTHENTICATE` carries when PLAIN sends the secret: authorization
	/// identity, authentication identity and password, split by NUL.
	static var expectedPayload: String {
		Data("\(account)\0\(account)\0\(secret)".utf8).base64EncodedString()
	}

	private enum Phase {
		case awaitingCapabilityList
		case negotiating
		case awaitingMechanism
		case awaitingPayload
		case authenticationEnded
		case registered
	}

	let answer: Answer
	private var phase = Phase.awaitingCapabilityList
	private var sawNick = false
	private var sawUser = false
	private(set) var passCount = 0
	private(set) var payloadCount = 0
	private(set) var payloadMatched = false

	/// Whether registration finished, after which the ordinary fixture takes over.
	var isRegistered: Bool {
		phase == .registered
	}

	init(answer: Answer) {
		self.answer = answer
	}

	/// What the scenario checks once the client has registered, in one line
	/// with no payload in it.
	var evidence: String {
		"pass=\(passCount) payloads=\(payloadCount) matched=\(payloadMatched)"
	}

	var expectedEvidence: String {
		switch answer {
		case .decline: "pass=0 payloads=0 matched=false"
		case .send: "pass=1 payloads=1 matched=true"
		}
	}

	mutating func receive(_ line: String) throws -> [String] {
		try checkForLeaks(line)
		switch line {
		case "CAP LS 302", "CAP LS :302":
			guard phase == .awaitingCapabilityList else { throw Self.unexpected("capability list") }
			phase = .negotiating
			return [":e2e.local CAP * LS :sasl=PLAIN"]
		case "PASS \(Self.serverSecret)", "PASS :\(Self.serverSecret)":
			guard answer == .send, phase == .negotiating, sawNick == false, passCount == 0 else {
				throw HarnessFailure.assertion("PASS reached the peer out of order or without consent; payload withheld")
			}
			passCount += 1
			return []
		case "NICK e2euser", "NICK :e2euser":
			guard phase == .negotiating, sawNick == false, answer == .decline || passCount == 1 else {
				throw Self.unexpected("NICK")
			}
			sawNick = true
			return []
		case "USER e2euser 0 * :Synthetic E2E User":
			guard sawNick, sawUser == false else { throw Self.unexpected("USER") }
			sawUser = true
			return []
		case "CAP REQ :sasl", "CAP REQ sasl":
			guard answer == .send, phase == .negotiating, sawUser else {
				throw HarnessFailure.assertion("SASL was requested after the user declined; payload withheld")
			}
			phase = .awaitingMechanism
			return [":e2e.local CAP * ACK :sasl"]
		case "AUTHENTICATE PLAIN":
			guard phase == .awaitingMechanism else { throw Self.unexpected("mechanism") }
			phase = .awaitingPayload
			return ["AUTHENTICATE +"]
		case "CAP END", "CAP :END":
			let ready = switch answer {
			case .decline: phase == .negotiating
			case .send: phase == .authenticationEnded
			}
			guard ready, sawNick, sawUser else { throw Self.unexpected("CAP END") }
			phase = .registered
			return FixtureProtocol.welcome
		default:
			guard line.hasPrefix("AUTHENTICATE ") else { throw Self.unexpected("command") }
			return try receivePayload(line)
		}
	}

	/// A secret anywhere but in the one place the Send answer allows it is a
	/// leak, whatever command carried it.
	private func checkForLeaks(_ line: String) throws {
		let carriesAccountSecret = line.contains(Self.secret) || line.contains(Self.expectedPayload)
		if carriesAccountSecret, !(answer == .send && phase == .awaitingPayload && line.hasPrefix("AUTHENTICATE ")) {
			throw HarnessFailure.assertion("The account secret reached the peer outside the permitted payload; payload withheld")
		}
		if line.contains(Self.serverSecret), !(answer == .send && line.hasPrefix("PASS ")) {
			throw HarnessFailure.assertion("The server secret reached the peer outside PASS; payload withheld")
		}
	}

	/// Any `AUTHENTICATE` line that names neither the mechanism nor an abort.
	private mutating func receivePayload(_ line: String) throws -> [String] {
		guard phase == .awaitingPayload else { throw Self.unexpected("payload") }
		payloadCount += 1
		guard payloadCount == 1, line == "AUTHENTICATE " + Self.expectedPayload else {
			throw HarnessFailure.assertion("The AUTHENTICATE payload was not the expected credentials; payload withheld")
		}
		payloadMatched = true
		phase = .authenticationEnded
		return [
			":e2e.local 900 e2euser e2euser!e2euser@localhost e2euser :You are now logged in as e2euser",
			":e2e.local 903 e2euser :SASL authentication successful",
		]
	}

	private static func unexpected(_ what: String) -> HarnessFailure {
		.assertion("Unexpected \(what) in the credential consent exchange; payload withheld")
	}
}
