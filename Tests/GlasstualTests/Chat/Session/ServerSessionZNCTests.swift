// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Security
import Testing

/// ZNC's `buffextras` module replays joins, parts, mode changes and the rest as
/// ordinary chat, and the session turns them back into the events they describe
/// before anything else reads the line. The rewriting is what these pin. The
/// `znc.in/tlsinfo` batch that carries the bouncer's certificate chain is
/// driven through real batch lines, so the session's own batch handling arms
/// and clears the state these read.
@MainActor
@Suite("ZNC bouncer interception")
struct ServerSessionZNCTests {
	private func session() -> TestServerSession {
		let session = TestServerSession()
		session.znc.isConnected = true
		return session
	}

	private func intercepted(_ line: String, on session: TestServerSession) throws -> Message? {
		let message = try #require(Message(line: line, on: session))
		return session.interceptZNCServerInput(message)
	}

	private func replay(_ body: String, on session: TestServerSession) throws -> Message? {
		try intercepted(":*buffextras!znc@znc.in PRIVMSG #chat :\(body)", on: session)
	}

	@Test("A replayed join becomes a JOIN from the person who joined")
	func replayedJoinBecomesAJoin() throws {
		let session = session()
		let rewritten = try #require(try replay("alice!user@host joined", on: session))

		#expect(rewritten.command == "JOIN")
		#expect(rewritten.params == ["#chat"])
		#expect(rewritten.sender.nickname == "alice")
		#expect(rewritten.sender.username == "user")
		#expect(rewritten.sender.address == "host")
		#expect(rewritten.sender.isServer == false)
		#expect(rewritten.isPrintOnlyMessage)
	}

	@Test("A replayed nickname change carries the new nickname as its parameter")
	func replayedNickChangeCarriesTheNewNickname() throws {
		let session = session()
		let rewritten = try #require(try replay("alice!user@host is now known as alicia", on: session))

		#expect(rewritten.command == "NICK")
		#expect(rewritten.params == ["#chat", "alicia"])
	}

	@Test(
		"A replayed part carries its comment in either spelling",
		arguments: [
			("alice!user@host parted with message: [so long]", "so long"),
			("alice!user@host parted: so long", "so long"),
			("alice!user@host parted with message: []", ""),
		]
	)
	func replayedPartCarriesItsComment(_ replayed: (line: String, comment: String)) throws {
		let session = session()
		let rewritten = try #require(try replay(replayed.line, on: session))

		#expect(rewritten.command == "PART")
		#expect(rewritten.params == ["#chat", replayed.comment])
	}

	@Test(
		"A replayed quit carries its comment in either spelling",
		arguments: [
			("alice!user@host quit with message: [bye]", "bye"),
			("alice!user@host quit: bye", "bye"),
		]
	)
	func replayedQuitCarriesItsComment(_ replayed: (line: String, comment: String)) throws {
		let session = session()
		let rewritten = try #require(try replay(replayed.line, on: session))

		#expect(rewritten.command == "QUIT")
		#expect(rewritten.params == ["#chat", replayed.comment])
	}

	@Test(
		"A replayed kick carries its target and, where there is one, its reason",
		arguments: [
			("alice!user@host kicked bob with reason: rude", ["#chat", "bob", "rude"]),
			("alice!user@host kicked bob Reason: [rude]", ["#chat", "bob", "rude"]),
			("alice!user@host kicked bob Reason: []", ["#chat", "bob"]),
		]
	)
	func replayedKickCarriesItsTargetAndReason(_ replayed: (line: String, params: [String])) throws {
		let session = session()
		let rewritten = try #require(try replay(replayed.line, on: session))

		#expect(rewritten.command == "KICK")
		#expect(rewritten.params == replayed.params)
	}

	/// The mode string and each of its arguments are separate IRC parameters.
	/// Joining them made "+ov nick1 nick2" one parameter, which the MODE
	/// handler cannot read.
	@Test("A replayed mode change splits its arguments into parameters of their own")
	func replayedModeChangeSplitsItsArguments() throws {
		let session = session()
		let rewritten = try #require(try replay("alice!user@host set mode: +ov bob carol", on: session))

		#expect(rewritten.command == "MODE")
		#expect(rewritten.params == ["#chat", "+ov", "bob", "carol"])
	}

	@Test("A replayed topic change is dropped, because the server sends the topic itself")
	func replayedTopicChangeIsDropped() throws {
		let session = session()

		#expect(try replay("alice!user@host changed the topic to: hello", on: session) == nil)
	}

	@Test("A replay of the local user's own event is dropped")
	func replayOfTheLocalUserIsDropped() throws {
		let session = session()
		session.userNickname = "me"

		#expect(try replay("me!user@host joined", on: session) == nil)
	}

	/// A token that is not a hostmask names the server, not a person.
	@Test("A replay whose first token is not a hostmask is attributed to the server")
	func replayFromAServerKeepsItsName() throws {
		let session = session()
		let rewritten = try #require(try replay("irc.example.net set mode: +n", on: session))

		#expect(rewritten.command == "MODE")
		#expect(rewritten.sender.nickname == "irc.example.net")
		#expect(rewritten.sender.isServer)
	}

	/// A "!" only a person's hostmask has, so an identd value the hostmask grammar
	/// refuses still names the person and never the server.
	@Test("A replay from a hostmask with an unusable username is attributed to the person")
	func replayWithUnusableUsernameNamesThePerson() throws {
		let session = session()
		let rewritten = try #require(try replay("alice!us!er@host joined", on: session))

		#expect(rewritten.command == "JOIN")
		#expect(rewritten.sender.nickname == "alice")
		#expect(rewritten.sender.username == nil)
		#expect(rewritten.sender.isServer == false)
	}

	/// The module's own text is not an event, so it is shown as it arrived,
	/// attributed to whoever the replay names.
	@Test("Replayed text that describes no event is printed as it arrived")
	func unrecognisedReplayIsPrintedAsItArrived() throws {
		let session = session()
		let rewritten = try #require(try replay("alice!user@host did something new", on: session))

		#expect(rewritten.command == "PRIVMSG")
		#expect(rewritten.params == ["#chat", "alice!user@host did something new"])
		#expect(rewritten.sender.nickname == "alice")
		#expect(rewritten.isPrintOnlyMessage)
	}

	@Test("A playback module's buffer-cleared notice is dropped while the capability is on")
	func playbackBufferClearedNoticeIsDropped() throws {
		let session = session()
		session.capabilityNegotiation.enable(.zncPlaybackModule)
		let line = ":*playback!znc@znc.in PRIVMSG me :" +
			"The playback buffer for [user] channels matching [*] has been cleared."

		#expect(try intercepted(line, on: session) == nil)
	}

	@Test("Nothing is intercepted when the connection is not a ZNC bouncer")
	func nothingIsInterceptedOffZNC() throws {
		let session = TestServerSession()
		let message = try #require(
			Message(line: ":*buffextras!znc@znc.in PRIVMSG #chat :alice!user@host joined", on: session)
		)

		#expect(session.interceptZNCServerInput(message)?.params == message.params)
	}

	// MARK: - znc.in/tlsinfo

	private static let certificateInfoOpening = ":irc.znc.in BATCH +t znc.in/tlsinfo"
	private static let certificateInfoClosing = ":irc.znc.in BATCH -t"

	private func certificateInfoSession(isZNC: Bool = true) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		session.enableCapability(.batch)
		session.enableCapability(.messageTags)
		session.isLoggedIn = true
		session.forwardsProcessedMessages = true
		session.znc.isConnected = isZNC
		return session
	}

	/// A line from the bouncer's `tlsinfo` module, inside the batch unless told otherwise.
	private func certificateInfoLine(_ chunk: String, sender: String = "znc.in", inBatch: Bool = true) -> String {
		"\(inBatch ? "@batch=t " : ""):\(sender) CERTINFO me :\(chunk)"
	}

	/// Feeds lines the way the socket reader does: batch bookkeeping first, then
	/// `BATCH` itself, then everything else through the real dispatch.
	private func feed(_ lines: [String], to session: TestServerSession) throws {
		for line in lines {
			let message = try #require(Message(line: line, on: session))

			if session.filterBatchCommandIncomingData(message) {
				continue
			}

			if message.command == "BATCH" {
				session.receiveBatch(message)
			} else {
				session.processIncomingMessage(message)
			}
		}
	}

	private func feedCertificateInfo(
		_ chunks: [String],
		closing: Bool = true,
		to session: TestServerSession
	) throws {
		let lines = [Self.certificateInfoOpening]
			+ chunks.map { certificateInfoLine($0) }
			+ (closing ? [Self.certificateInfoClosing] : [])
		try feed(lines, to: session)
	}

	private func makeChunk(ofLength length: Int) -> String {
		String(repeating: "A", count: length)
	}

	/// A chain a bouncer would send: two certificates, 64 characters to a line.
	private static let pemChain = """
	-----BEGIN CERTIFICATE-----
	MIIBazCCARKgAwIBAgIUDTrdlMHsPkONCHnH/4EdehcB5NcwCgYIKoZIzj0EAwIw
	GzEZMBcGA1UEAwwQZ2xhc3N0dWFsLXRlc3QtYTAgFw0yNjExMTExMzA1NDNaGA8y
	MTI2MTAxODEzMDU0M1owGzEZMBcGA1UEAwwQZ2xhc3N0dWFsLXRlc3QtYTBZMBMG
	ByqGSM49AgEGCCqGSM49AwEHA0IABK/z1c7DQ0hsDswEszLPU8KmYYYTsp/VFUR+
	dRxynBpP8sHbZaJ6bwF7F8iC5yjLgnenri1jwPY+l4KA8m5NxNajMjAwMB0GA1Ud
	DgQWBBRoFRHmjyuK0nAFNEAKiS/JXFpbBTAPBgNVHRMBAf8EBTADAQH/MAoGCCqG
	SM49BAMCA0cAMEQCIAtBM/z1SQZgDj8vfWPLc2ZCxDKsSVLoA8yUglyONw0lAiAv
	14757dspUlAlqvUNVe1FmiPyR1096K3CDoZLtvDQFg==
	-----END CERTIFICATE-----
	-----BEGIN CERTIFICATE-----
	MIIBazCCARKgAwIBAgIUAKoQIc1PjWZVlujHhjgPJGv4TRcwCgYIKoZIzj0EAwIw
	GzEZMBcGA1UEAwwQZ2xhc3N0dWFsLXRlc3QtYjAgFw0yNjExMTExMzA1NDNaGA8y
	MTI2MTAxODEzMDU0M1owGzEZMBcGA1UEAwwQZ2xhc3N0dWFsLXRlc3QtYjBZMBMG
	ByqGSM49AgEGCCqGSM49AwEHA0IABDX5O7R6VqOqO9xMGyBbB7Dudd7uGaAc1xaL
	zGcOjW3DJD9bUvL54+Bt4NodFnJS7xo1EWWXQlYJOTXJRoudhoKjMjAwMB0GA1Ud
	DgQWBBScy2UHeb4BMNZ1ZVtysAs9yx1hADAPBgNVHRMBAf8EBTADAQH/MAoGCCqG
	SM49BAMCA0cAMEQCIE8WeS9ihB9WHIUEWJU9/XqRrTuUqD5oyfNvruJXpuS7AiAX
	RFT7IoPiYV/5AwKj0I6w4eiaq3Sj57MQaK+CX476zg==
	-----END CERTIFICATE-----
	"""

	private static var pemChainLines: [String] {
		pemChain.split(separator: "\n").map(String.init)
	}

	@Test("A tlsinfo batch accumulates its chunks, one per line, and is complete once it closes")
	func certificateInfoBatchAccumulatesItsChunks() throws {
		let session = certificateInfoSession()
		let chunks = ["first chunk", "second chunk", "third chunk"]

		try feedCertificateInfo(chunks, closing: false, to: session)
		#expect(session.znc.isSendingCertificateInfo)
		// The chunks wait in the batch until it closes.
		#expect(session.znc.certificateChainText == "")

		try feed([Self.certificateInfoClosing], to: session)

		#expect(session.znc.isSendingCertificateInfo == false)
		#expect(session.znc.certificateChainText == "first chunk\nsecond chunk\nthird chunk\n")
		#expect(session.zncBouncerCertificateChainData == Data("first chunk\nsecond chunk\nthird chunk\n".utf8))
	}

	@Test("The chain is withheld while the batch is open and offered once it has closed")
	func certificateInfoChainIsOnlyOfferedOnceComplete() throws {
		let session = certificateInfoSession()

		try feedCertificateInfo(["a chunk"], closing: false, to: session)
		#expect(session.zncBouncerCertificateChainData == nil)

		try feed([Self.certificateInfoClosing], to: session)
		#expect(session.zncBouncerCertificateChainData != nil)
	}

	@Test("A second tlsinfo batch replaces the chain rather than extending it")
	func secondCertificateInfoBatchReplacesTheChain() throws {
		let session = certificateInfoSession()

		try feedCertificateInfo(["old chain"], to: session)
		try feedCertificateInfo(["new chain"], to: session)

		#expect(session.znc.certificateChainText == "new chain\n")
	}

	@Test("A CERTINFO line outside a tlsinfo batch is ignored")
	func certificateInfoOutsideABatchIsIgnored() throws {
		let session = certificateInfoSession()

		try feed([certificateInfoLine("before any batch", inBatch: false)], to: session)
		#expect(session.znc.certificateChainText == nil)

		try feedCertificateInfo(["inside the batch"], to: session)
		try feed([certificateInfoLine("after the batch", inBatch: false)], to: session)
		#expect(session.znc.certificateChainText == "inside the batch\n")
	}

	@Test("An untagged CERTINFO line that arrives while a tlsinfo batch is open is not appended")
	func untaggedCertificateInfoDuringAnOpenBatchIsIgnored() throws {
		let session = certificateInfoSession()

		try feed([
			Self.certificateInfoOpening,
			certificateInfoLine("genuine chunk"),
			certificateInfoLine("injected chunk", inBatch: false),
			Self.certificateInfoClosing,
		], to: session)

		#expect(session.znc.certificateChainText == "genuine chunk\n")
	}

	@Test(
		"A CERTINFO chunk from anyone but the bouncer's own sender is not appended",
		arguments: ["evil!user@host", "irc.example.net", "znc.in!user@host", "*status!znc@znc.in"]
	)
	func certificateInfoFromAnotherSenderIsIgnored(_ sender: String) throws {
		let session = certificateInfoSession()

		try feed([
			Self.certificateInfoOpening,
			certificateInfoLine("forged chunk", sender: sender),
			certificateInfoLine("genuine chunk"),
			Self.certificateInfoClosing,
		], to: session)

		#expect(session.znc.certificateChainText == "genuine chunk\n")
	}

	@Test(
		"A CERTINFO line with a chunk outside 2...65 characters, or the wrong shape, is ignored",
		arguments: [
			"@batch=t :znc.in CERTINFO me :x",
			"@batch=t :znc.in CERTINFO me :\(String(repeating: "A", count: 66))",
			"@batch=t :znc.in CERTINFO me extra :a chunk",
			"@batch=t :znc.in CERTINFO :a chunk",
		]
	)
	func certificateInfoWithAnUnacceptableChunkIsIgnored(_ line: String) throws {
		let session = certificateInfoSession()

		try feed([Self.certificateInfoOpening, line, Self.certificateInfoClosing], to: session)

		#expect(session.znc.certificateChainText == "")
	}

	/// The length is checked before the chunk is appended, so the chain can
	/// finish up to one chunk past the ceiling. What matters is that it stops.
	@Test("The chain stops growing once it reaches its ceiling")
	func certificateInfoChainStopsAtItsCeiling() throws {
		let session = certificateInfoSession()
		let ceiling = InboundEventPolicy.maximumCertificateChainLength
		let chunk = makeChunk(ofLength: 65)

		try feed([Self.certificateInfoOpening], to: session)
		for _ in 0 ..< 1100 {
			let message = try #require(Message(line: certificateInfoLine(chunk), on: session))
			session.receiveCertInfo(message)
		}

		let length = try #require(session.znc.certificateChainText).utf16.count
		#expect(length >= ceiling)
		#expect(length < ceiling + 66)

		let further = try #require(Message(line: certificateInfoLine("one more chunk"), on: session))
		session.receiveCertInfo(further)
		#expect(session.znc.certificateChainText?.utf16.count == length)
	}

	@Test("A chain sent past the ceiling in one batch is cut off at it")
	func oversizedCertificateInfoBatchIsCutOff() throws {
		let session = certificateInfoSession()
		let ceiling = InboundEventPolicy.maximumCertificateChainLength

		try feedCertificateInfo(Array(repeating: makeChunk(ofLength: 65), count: 1100), to: session)

		let length = try #require(session.zncBouncerCertificateChainData).count
		#expect(length >= ceiling)
		#expect(length < ceiling + 66)
	}

	@Test("A bouncer that is not a ZNC does not get to arm the chain")
	func certificateInfoBatchIsIgnoredOffZNC() throws {
		let session = certificateInfoSession(isZNC: false)

		try feedCertificateInfo(["a chunk"], closing: false, to: session)
		#expect(session.znc.isSendingCertificateInfo == false)

		try feed([Self.certificateInfoClosing], to: session)
		#expect(session.znc.certificateChainText == "")
		#expect(session.zncBouncerCertificateChainData == nil)
	}

	@Test("Disconnecting forgets the chain, whether the batch finished or not", arguments: [true, false])
	func disconnectingForgetsTheCertificateChain(batchFinished: Bool) throws {
		let session = certificateInfoSession()
		try feedCertificateInfo(["a chunk"], closing: batchFinished, to: session)

		session.resetAllPropertyValues()

		#expect(session.znc.isSendingCertificateInfo == false)
		#expect(session.znc.certificateChainText == nil)
		#expect(session.zncBouncerCertificateChainData == nil)
	}

	@Test("A chain sent as a PEM sequence imports as the certificates it holds")
	func certificateChainImportsAsPEM() throws {
		let session = certificateInfoSession()
		try feedCertificateInfo(Self.pemChainLines, to: session)

		let data = try #require(session.zncBouncerCertificateChainData)
		let certificates = try #require(ServerSession.certificates(fromPEMSequence: data))
		let subjects = certificates.compactMap { SecCertificateCopySubjectSummary($0) as String? }

		#expect(subjects == ["glasstual-test-a", "glasstual-test-b"])
	}

	@Test(
		"Text that is not a PEM sequence imports as nothing",
		arguments: [
			"",
			"not a certificate",
			"-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n",
		]
	)
	func nonCertificateTextImportsAsNothing(_ text: String) {
		#expect(ServerSession.certificates(fromPEMSequence: Data(text.utf8)) == nil)
	}
}
