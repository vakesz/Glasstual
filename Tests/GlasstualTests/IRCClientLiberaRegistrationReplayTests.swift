import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** Registration against Libera.Chat, replayed line for line.

 Libera holds its `CAP LS` answer until the ident lookup has finished, so the
 first thing the client hears is a run of pre-registration notices, then the
 listing, then the acknowledgements. Captured 2026-09-09 with a plain probe. */
@MainActor
@Suite("Libera registration replay")
struct IRCClientLiberaRegistrationReplayTests {
	static let preRegistrationNotices = [
		":iridium.libera.chat NOTICE * :*** Checking Ident",
		":iridium.libera.chat NOTICE * :*** Looking up your hostname...",
		":iridium.libera.chat NOTICE * :*** Found your hostname: catv-1-2-3-4.example.net",
		":iridium.libera.chat NOTICE * :*** No Ident response",
	]

	static let capabilityListing = ":iridium.libera.chat CAP * LS :account-notify away-notify batch chghost "
		+ "extended-join multi-prefix sasl=ECDSA-NIST256P-CHALLENGE,EXTERNAL,PLAIN,SCRAM-SHA-512 tls account-tag "
		+ "cap-notify echo-message invite-notify labeled-response message-tags no-implicit-names server-time "
		+ "solanum.chat/identify-msg solanum.chat/oper solanum.chat/realhost"

	static let welcome = [
		":iridium.libera.chat 001 me :Welcome to the Libera.Chat Internet Relay Chat Network me",
		":iridium.libera.chat 002 me :Your host is iridium.libera.chat[188.240.145.100/6697], running version solanum-1.0-dev",
		":iridium.libera.chat 003 me :This server was created Thu Aug 27 2026 at 00:26:49 UTC",
		":iridium.libera.chat 004 me iridium.libera.chat solanum-1.0-dev DGIMQRSZaghiopsuwz CFILMPQRSTbcefgijklmnopqrstuvz bkloveqjfI",
		":iridium.libera.chat 005 me ETRACE KNOCK SAFELIST ELIST=CMNTU MONITOR=100 FNC WHOX CALLERID=g "
			+ "ACCOUNTEXTBAN=a CHANTYPES=# EXCEPTS INVEX :are supported by this server",
		":iridium.libera.chat 005 me CHANMODES=eIbq,k,flj,CFLMPQRSTcgimnprstuz CHANLIMIT=#:250 PREFIX=(ov)@+ "
			+ "MAXLIST=bqeI:100 MODES=4 NETWORK=Libera.Chat STATUSMSG=@+ CASEMAPPING=rfc1459 NICKLEN=16 "
			+ "MAXNICKLEN=16 CHANNELLEN=50 TOPICLEN=390 :are supported by this server",
		":iridium.libera.chat 005 me DEAF=D TARGMAX=NAMES:1,LIST:1,KICK:1,WHOIS:1,PRIVMSG:4,NOTICE:4,ACCEPT:,MONITOR: "
			+ "EXTBAN=$,agjrxz CLIENTTAGDENY=*,-typing :are supported by this server",
		":iridium.libera.chat 251 me :There are 62 users and 31421 invisible on 30 servers",
		":iridium.libera.chat 375 me :- iridium.libera.chat Message of the Day - ",
		":iridium.libera.chat 372 me :- This server provided by NORDUnet/SUNET",
		":iridium.libera.chat 376 me :End of /MOTD command.",
		":me MODE me :+Ziw",
	]

	@Test("Without SASL the client ends negotiation after the delayed listing and logs in")
	func registersWithoutSASL() throws {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"], nicknamePassword: nil)
		client.forwardsProcessedMessages = true
		client.isConnected = true

		try replayRegistration(on: client)

		#expect(
			capabilityCommands(of: client).last == "END",
			"CAP END never went out: \(capabilityCommands(of: client))"
		)

		for line in Self.welcome {
			try receive(line, on: client)
		}

		#expect(client.isLoggedIn, "the client never treated 001 as a completed login")
	}

	@Test("With a password the client authenticates with SASL PLAIN, ends negotiation and logs in")
	func registersWithSASL() throws {
		let client = GLTTestClient(
			configDictionary: ["nickname": "me", "username": "me"],
			nicknamePassword: "secret"
		)
		client.forwardsProcessedMessages = true
		client.isConnected = true

		try replayRegistration(on: client) { client in
			guard client.isCapabilityEnabled(.isInSASLNegotiation) else { return }
			let sent = sentLines(of: client)
			if sent.contains("AUTHENTICATE PLAIN"),
			   !sent.contains(where: { $0.hasPrefix("AUTHENTICATE ") && $0 != "AUTHENTICATE PLAIN" })
			{
				try receive("AUTHENTICATE +", on: client)
			}
			if sentLines(of: client)
				.contains(where: {
					$0.hasPrefix("AUTHENTICATE ") && $0 != "AUTHENTICATE PLAIN" && $0 != "AUTHENTICATE +"
				})
			{
				try receive(":iridium.libera.chat 900 me me!me@host me :You are now logged in as me", on: client)
				try receive(":iridium.libera.chat 903 me :SASL authentication successful", on: client)
			}
		}

		#expect(
			capabilityCommands(of: client).last == "END",
			"CAP END never went out: \(capabilityCommands(of: client)) sent=\(sentLines(of: client))"
		)

		for line in Self.welcome {
			try receive(line, on: client)
		}

		#expect(client.isLoggedIn, "the client never treated 001 as a completed login")
	}

	/** What reaches the wire, not what the negotiation meant to ask for: the
	 batched request is one line with a trailing parameter, and the answer to
	 that line matches every name back so `CAP END` follows. */
	@Test("A batched request goes out as one trailing parameter that Libera acknowledges whole")
	func batchedRequestIsATrailingParameterOnTheWire() throws {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"], nicknamePassword: nil)
		client.forwardsProcessedMessages = true
		client.forwardsSentLines = true
		client.isConnected = true

		try replayRegistration(on: client)

		let requests = sentLines(of: client).filter { $0.hasPrefix("CAP REQ") }
		#expect(requests.isEmpty == false)
		for request in requests where request.contains(" ", after: "CAP REQ ".count) {
			#expect(request.hasPrefix("CAP REQ :"), "a multi-name request without its colon: \(request)")
		}
		#expect(sentLines(of: client).last == "CAP END", "CAP END never went out: \(sentLines(of: client))")
	}

	// MARK: - Replay

	/// Feeds the notices and the listing, then answers every `CAP REQ` the
	/// client sends with the acknowledgement Libera would give, until the
	/// client stops asking.
	private func replayRegistration(
		on client: GLTTestClient,
		afterEachAnswer: (GLTTestClient) throws -> Void = { _ in }
	) throws {
		for line in Self.preRegistrationNotices {
			try receive(line, on: client)
		}
		try receive(Self.capabilityListing, on: client)

		var answered = 0
		for _ in 0 ..< 10 {
			let requests = capabilityCommands(of: client).filter { $0.hasPrefix("REQ ") }
			guard requests.count > answered else { break }
			for request in requests[answered...] {
				let names = request.dropFirst("REQ ".count)
				try receive(":iridium.libera.chat CAP me ACK :\(names)", on: client)
			}
			answered = requests.count
			try afterEachAnswer(client)
		}
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))
		if message.commandNumeric > 0 {
			client.receiveNumericReply(message)
		} else {
			client.processIncomingMessage(message)
		}
	}

	private func capabilityCommands(of client: GLTTestClient) -> [String] {
		(client.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		(client.sentLines as NSArray).compactMap { $0 as? String }
	}
}

private extension String {
	/// Whether a space occurs past the first `offset` characters.
	func contains(_ character: Character, after offset: Int) -> Bool {
		dropFirst(offset).contains(character)
	}
}
