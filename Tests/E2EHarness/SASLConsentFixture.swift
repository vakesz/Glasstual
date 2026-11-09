import Foundation

/** The server side of the credential-consent prompt: SASL PLAIN is offered over
 TLS to a client that does not validate the certificate, so the client has to ask
 its user before the password goes anywhere.

 It owns registration for these scenarios, because the fixed list in
 `FixtureProtocol.registration` has no room for the capability exchange. What it
 records is what the server actually received: how many `AUTHENTICATE` payloads
 arrived and whether the client aborted instead. The secret is synthetic and no
 line, payload or failure message is ever printed; a failure names the shape of
 what went wrong and nothing it carried. */
struct SASLConsentFixture {
	/// What the user is expected to answer when the client asks.
	enum Answer {
		case decline
		case send
	}

	/// Not a credential for anything. The harness types it into the client's
	/// settings and this fixture looks for it on the wire.
	static let secret = "E2E_SASL_SYNTHETIC_SECRET"
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
		case awaitingAnswer
		case authenticationEnded
		case registered
	}

	let answer: Answer
	private var phase = Phase.awaitingCapabilityList
	private var sawNick = false
	private var sawUser = false
	private(set) var payloadCount = 0
	private(set) var payloadMatched = false
	private(set) var aborted = false

	/// Whether registration finished, after which the ordinary fixture takes over.
	var isRegistered: Bool {
		phase == .registered
	}

	init(answer: Answer) {
		self.answer = answer
	}

	/// What the harness checks after the client has quit, in one line with no
	/// payload in it.
	var evidence: String {
		"payloads=\(payloadCount) matched=\(payloadMatched) aborted=\(aborted)"
	}

	var expectedEvidence: String {
		switch answer {
		case .decline: "payloads=0 matched=false aborted=true"
		case .send: "payloads=1 matched=true aborted=false"
		}
	}

	mutating func receive(_ line: String) throws -> [String] {
		/* The secret anywhere but in the one payload the Send answer allows is a
		 leak, whatever command carried it. */
		let carriesSecret = line.contains(Self.secret) || line.contains(Self.expectedPayload)
		if carriesSecret, !(answer == .send && phase == .awaitingAnswer && line.hasPrefix("AUTHENTICATE ")) {
			throw HarnessFailure.assertion("The account secret reached the peer outside the permitted payload; payload withheld")
		}
		switch line {
		case "CAP LS 302", "CAP LS :302":
			guard phase == .awaitingCapabilityList else { throw Self.unexpected("capability list") }
			phase = .negotiating
			return [":e2e.local CAP * LS :sasl=PLAIN"]
		case "NICK e2euser", "NICK :e2euser":
			guard phase != .awaitingCapabilityList, !sawNick else { throw Self.unexpected("NICK") }
			sawNick = true
			return []
		case "USER e2euser 0 * :Synthetic E2E User":
			guard phase != .awaitingCapabilityList, !sawUser else { throw Self.unexpected("USER") }
			sawUser = true
			return []
		case "CAP REQ :sasl", "CAP REQ sasl":
			guard phase == .negotiating else { throw Self.unexpected("capability request") }
			phase = .awaitingMechanism
			return [":e2e.local CAP * ACK :sasl"]
		case "AUTHENTICATE PLAIN":
			guard phase == .awaitingMechanism else { throw Self.unexpected("mechanism") }
			phase = .awaitingAnswer
			return ["AUTHENTICATE +"]
		case "AUTHENTICATE *":
			guard phase == .awaitingAnswer, answer == .decline else { throw Self.unexpected("abort") }
			aborted = true
			phase = .authenticationEnded
			return [":e2e.local 906 e2euser :SASL authentication aborted"]
		case "CAP END", "CAP :END":
			guard phase == .authenticationEnded, sawNick, sawUser else { throw Self.unexpected("CAP END") }
			phase = .registered
			return FixtureProtocol.welcome
		default:
			guard line.hasPrefix("AUTHENTICATE ") else { throw Self.unexpected("command") }
			return try receivePayload(line)
		}
	}

	/// Any `AUTHENTICATE` line that names neither the mechanism nor an abort.
	private mutating func receivePayload(_ line: String) throws -> [String] {
		guard phase == .awaitingAnswer else { throw Self.unexpected("payload") }
		payloadCount += 1
		guard answer == .send else {
			throw HarnessFailure.assertion("An AUTHENTICATE payload reached the peer after the user declined; payload withheld")
		}
		guard payloadCount == 1 else {
			throw HarnessFailure.assertion("More than one AUTHENTICATE payload reached the peer; payload withheld")
		}
		guard line == "AUTHENTICATE " + Self.expectedPayload else {
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
		.assertion("Unexpected \(what) in the SASL consent exchange; payload withheld")
	}
}
