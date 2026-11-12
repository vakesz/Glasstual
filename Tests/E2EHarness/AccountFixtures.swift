import Foundation

/** The server side of Register Account: `draft/account-registration`.

 The capability asks for an email address and allows an account name other
 than the nickname. `REGISTER` is answered with `VERIFICATION_REQUIRED`, and
 `VERIFY` with the one code this fixture issues completes it. The password is
 synthetic and is looked for only in `REGISTER`. */
struct AccountRegistrationFixture: ScriptedFixture {
	static let account = "e2eaccount"
	static let email = "e2e@example.invalid"
	static let password = "E2E_REGISTRATION_SECRET"
	static let code = "E2E-CODE-4242"

	var registration = CapabilityRegistration(
		offer: ["draft/account-registration=custom-account-name,email-required"]
	)
	private(set) var registerSeen = false
	private(set) var verified = false

	var finished: Bool {
		verified
	}

	var evidence: String {
		"register=\(registerSeen) verified=\(verified)"
	}

	static let expectedEvidence = "register=true verified=true"

	mutating func receive(_ line: ClientLine, pongSeen: Bool) throws -> [String]? {
		let text = line.text
		if text.contains(Self.password), text.hasPrefix("REGISTER ") == false {
			throw HarnessFailure.assertion("The registration password reached the peer outside REGISTER; payload withheld")
		}
		if text.hasPrefix("REGISTER ") {
			let expected = "REGISTER \(Self.account) \(Self.email) "
			guard pongSeen, registerSeen == false,
			      text == expected + Self.password || text == expected + ":" + Self.password
			else { throw HarnessFailure.assertion("REGISTER did not carry the account, email and password entered; payload withheld") }
			registerSeen = true
			return [":e2e.local REGISTER VERIFICATION_REQUIRED \(Self.account) :E2E_VERIFICATION_REQUIRED"]
		}
		if text.hasPrefix("VERIFY ") {
			guard registerSeen, verified == false,
			      text == "VERIFY \(Self.account) \(Self.code)" || text == "VERIFY \(Self.account) :\(Self.code)"
			else { throw HarnessFailure.assertion("VERIFY did not carry the account and the code entered; payload withheld") }
			verified = true
			return [":e2e.local VERIFY SUCCESS \(Self.account) :E2E_ACCOUNT_VERIFIED"]
		}
		return nil
	}
}

/** The server side of editing the user's own profile: `draft/metadata-2`.

 The client subscribes to the profile keys after the welcome, syncs the
 channel it joins, and sets `display-name`. The one value this fixture stores
 is the display name the scenario enters; it answers with `RPL_KEYVALUE`. */
struct MetadataFixture: ScriptedFixture {
	static let displayName = "E2E_DISPLAY_NAME"
	private static let keys = ["display-name", "avatar", "color"]

	var registration = CapabilityRegistration(
		offer: ["batch", "draft/metadata-2=max-subs=10,max-keys=10,max-value-bytes=300"]
	)
	private var channel = ScriptedChannel()
	private(set) var subscribed = false
	private(set) var stored: String?
	private var batches = 0

	var finished: Bool {
		stored == Self.displayName
	}

	var evidence: String {
		"subscribed=\(subscribed) stored=\(stored == Self.displayName)"
	}

	static let expectedEvidence = "subscribed=true stored=true"

	mutating func receive(_ line: ClientLine, pongSeen: Bool) throws -> [String]? {
		let text = line.text
		if let response = try channel.receive(text, pongSeen: pongSeen, burst: [
			":fixture!fixture@localhost PRIVMSG #e2e :E2E_CHANNEL_READY",
		]) {
			return response
		}
		guard text.hasPrefix("METADATA ") else { return nil }
		let fields = text.split(separator: " ", maxSplits: 3).map(String.init)
		guard fields.count >= 3 else { throw Self.unexpected("command") }
		switch (fields[1], fields[2]) {
		case ("*", "SUB"):
			let keys = fields.count > 3 ? fields[3].split(separator: " ")
				.map { $0.hasPrefix(":") ? String($0.dropFirst()) : String($0) } : []
			guard subscribed == false, keys.isEmpty == false, keys.allSatisfy(Self.keys.contains) else {
				throw Self.unexpected("subscription")
			}
			subscribed = true
			return [":e2e.local 770 e2euser " + keys.joined(separator: " ")]
		case (_, "SYNC"):
			let target = fields[1]
			guard subscribed, fields.count == 3, target == "*" || target == ScriptedChannel.name, target == "*" || channel.joined
			else { throw Self.unexpected("sync") }
			batches += 1
			let reference = "e2emeta\(batches)"
			let values = stored.map { ["@batch=\(reference) :e2e.local METADATA e2euser display-name * :\($0)"] } ?? []
			return [":e2e.local BATCH +\(reference) metadata \(target)"] + values + [":e2e.local BATCH -\(reference)"]
		case ("*", "SET"):
			guard subscribed, stored == nil, fields.count == 4,
			      fields[3] == "display-name \(Self.displayName)" || fields[3] == "display-name :\(Self.displayName)"
			else { throw HarnessFailure.assertion("METADATA SET was not the display name entered; payload withheld") }
			stored = Self.displayName
			return [":e2e.local 761 e2euser e2euser display-name * :\(Self.displayName)"]
		default:
			throw Self.unexpected("subcommand")
		}
	}

	private static func unexpected(_ what: String) -> HarnessFailure {
		.assertion("Unexpected METADATA \(what); payload withheld")
	}
}

/** The server side of the SASL mechanism choice and of Sign In Again.

 `SCRAM-SHA-256` is offered ahead of `PLAIN`, so a client that tries `PLAIN`
 first, and nothing else, is one that kept to the mechanism chosen in Server
 Properties. The first `PLAIN` exchange is refused with 904 and registration
 completes signed out; the second, which Sign In Again starts on the
 registered connection, succeeds. The secret is synthetic and is looked for
 only in the `AUTHENTICATE` payload. */
struct SASLSignInFixture: ScriptedFixture {
	/// The `AUTHENTICATE` exchanges, apart from registration so one line can
	/// be offered to both.
	private struct Exchanges {
		var awaitingPayload = false
		/// `PLAIN` exchanges that ran to their payload.
		var attempts = 0
		var signedIn = false

		mutating func receive(_ line: String, acknowledged: Bool, registered: Bool) throws -> [String]? {
			guard line.hasPrefix("AUTHENTICATE ") else { return nil }
			guard acknowledged, signedIn == false else {
				throw HarnessFailure.assertion("AUTHENTICATE without an acknowledged sasl capability or after signing in")
			}
			guard awaitingPayload else {
				guard line == "AUTHENTICATE PLAIN" else {
					throw HarnessFailure.assertion("SASL started with a mechanism other than the one chosen")
				}
				awaitingPayload = true
				return ["AUTHENTICATE +"]
			}
			guard line == "AUTHENTICATE " + SASLConsentFixture.expectedPayload else {
				throw HarnessFailure.assertion("The AUTHENTICATE payload was not the expected credentials; payload withheld")
			}
			awaitingPayload = false
			attempts += 1
			// The first exchange is refused; it has to be the one registration ran.
			guard attempts > 1 else {
				guard registered == false else {
					throw HarnessFailure.assertion("Registration completed without trying to sign in")
				}
				return [":e2e.local 904 e2euser :E2E_SASL_REFUSED"]
			}
			guard registered else {
				throw HarnessFailure.assertion("The second SASL exchange ran before registration completed")
			}
			signedIn = true
			return [
				":e2e.local 900 e2euser e2euser!e2euser@localhost e2euser :You are now logged in as e2euser",
				":e2e.local 903 e2euser :SASL authentication successful",
			]
		}
	}

	var registration = CapabilityRegistration(offer: ["sasl=SCRAM-SHA-256,PLAIN"])
	private var exchanges = Exchanges()

	var finished: Bool {
		exchanges.signedIn
	}

	var evidence: String {
		"attempts=\(exchanges.attempts) signedIn=\(exchanges.signedIn)"
	}

	static let expectedEvidence = "attempts=2 signedIn=true"

	mutating func register(_ line: String) throws -> [String] {
		try checkForLeaks(line)
		var exchanges = exchanges
		defer { self.exchanges = exchanges }
		let acknowledged = registration.acknowledged.contains("sasl")
		return try registration.receive(line) { line in
			try exchanges.receive(line, acknowledged: acknowledged, registered: false)
		}
	}

	mutating func receive(_ line: ClientLine, pongSeen _: Bool) throws -> [String]? {
		try checkForLeaks(line.text)
		return try exchanges.receive(line.text, acknowledged: registration.acknowledged.contains("sasl"), registered: true)
	}

	private func checkForLeaks(_ line: String) throws {
		let carriesSecret = line.contains(SASLConsentFixture.secret) || line.contains(SASLConsentFixture.expectedPayload)
		if carriesSecret, !(exchanges.awaitingPayload && line.hasPrefix("AUTHENTICATE ")) {
			throw HarnessFailure.assertion("The account secret reached the peer outside the permitted payload; payload withheld")
		}
	}
}
