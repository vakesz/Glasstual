// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Who the session thinks is present, and under which spelling of their name.

 Every question here is a casemapping question or a rename question: RFC 1459
 §2.2 makes `[`, `]`, `\` and `~` the upper-case forms of `{`, `}`, `|` and
 `^`, and the server decides which mapping is in force. Comparing nicknames any
 other way splits one person into two, or merges two into one. */
@MainActor
@Suite("Inbound presence tracking")
struct InboundPresenceTrackingTests {
	private func session(nickname: String = "me") -> TestServerSession {
		TestServerSession(configDictionary: ["nickname": nickname, "username": nickname])
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))

		if message.commandNumeric > 0 {
			session.receiveNumericReply(message)
		} else {
			session.forwardsProcessedMessages = true
			session.processIncomingMessage(message)
		}
	}

	private func query(_ name: String, on session: TestServerSession) throws -> Conversation {
		let query = try #require(session.findConversationOrCreate(name, isDirect: true))

		query.activate()

		return query
	}

	private func trackingEntry(forNickname nickname: String) -> AddressBookEntry {
		var entry = AddressBookEntry.newUserTrackingEntry()
		entry.hostmask = nickname

		return entry
	}

	// MARK: - Address-book tracking

	/** A NICK is reported to the address book twice: once for the entry the old
	 nickname matched and once for the entry the new one does. Both carry the
	 same sender, who is the person under their *old* name, so recording the
	 second transition against the sender signed the wrong entry on. */
	@Test("Renaming into a tracked nickname signs that nickname on")
	func renameIntoATrackedNicknameSignsThatNicknameOn() throws {
		let session = session()
		session.config.ignoreList = [trackingEntry(forNickname: "bob")]
		session.markAsLoggedIn()
		session.populateISONTrackedUsersList()

		#expect(session.trackedUsers.status(ofUser: "bob") == .notAvailable)

		try receive(":alice!ali@example.org NICK bob", on: session)

		#expect(session.trackedUsers.status(ofUser: "bob") == .available)
		#expect(session.trackedUsers.status(ofUser: "alice") == .unknown)
	}

	/** An `/ignore spammer` compiles to the same `spammer!*@*` mask a tracking
	 rule for that person does, so the match cache answers with it. Taking the
	 answer unfiltered made WATCH and MONITOR numerics treat the ignore as
	 something to report presence for. */
	@Test("An ignore rule is not mistaken for a tracking rule")
	func anIgnoreRuleIsNotATrackingRule() {
		let session = session()
		session.config.ignoreList = [AddressBookEntry.newIgnoreEntry(forHostmask: "spammer!*@*")]

		#expect(session.findUserTrackingAddressBookEntry(forNickname: "spammer") == nil)

		session.config.ignoreList.append(trackingEntry(forNickname: "spammer"))
		session.clearAddressBookCache()

		let entry = session.findUserTrackingAddressBookEntry(forNickname: "spammer")

		#expect(entry?.trackingNickname == "spammer")
	}

	// MARK: - Queries

	/** Two queries cannot share a name. The query already open under the new
	 nickname keeps it; the renamed one is closed rather than left following a
	 name that now belongs to somebody else, which is what stranded it — never
	 renamed, and never taken off the watch list. */
	@Test("A rename into a nickname with an open query closes the renamed query")
	func renameIntoAnOpenQueryClosesTheRenamedOne() throws {
		let session = session()
		let aliceQuery = try query("alice", on: session)
		let bobQuery = try query("bob", on: session)
		_ = session.findUserOrCreate("alice")

		bobQuery.deactivate()

		try receive(":alice!ali@example.org NICK bob", on: session)

		#expect(aliceQuery.name == "alice")
		#expect(aliceQuery.isActive == false)
		#expect(bobQuery.isActive)
		#expect(session.findConversation("bob") === bobQuery)
	}

	/// With no query in the way the rename still follows its peer.
	@Test("A rename with no query in the way renames the query")
	func renameWithNoCollisionRenamesTheQuery() throws {
		let session = session()
		let aliceQuery = try query("alice", on: session)
		_ = session.findUserOrCreate("alice")

		try receive(":alice!ali@example.org NICK bob", on: session)

		#expect(aliceQuery.name == "bob")
		#expect(session.findConversation("bob") === aliceQuery)
	}

	/// `/setqueryname` looks the new name up under the server's casemapping, so
	/// a change of case finds the query being renamed — which it offered to
	/// delete as a conflicting conversation.
	@Test("Renaming a query to a change of case keeps the query")
	func setQueryNameToAChangeOfCaseKeepsTheQuery() throws {
		let session = session()
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		let peerQuery = try query("bob", on: session)

		session.sendCommand("setqueryname Bob", completeTarget: true, target: "bob")

		#expect(peerQuery.name == "Bob")
		#expect(session.findConversation("bob") === peerQuery)
		#expect(session.sentLines.count == 0)
	}

	@Test("Renaming a query moves the peer's MONITOR entry to the new nickname")
	func setQueryNameMovesTheMonitorEntry() throws {
		let session = session()
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.enableCapability(.monitorCommand)
		let peerQuery = try query("bob", on: session)
		session.sentLines.removeAllObjects()

		session.sendCommand("setqueryname carol", completeTarget: true, target: "bob")

		#expect(peerQuery.name == "carol")
		#expect(session.sentLines.compactMap { $0 as? String } == ["MONITOR - bob", "MONITOR + carol"])
	}

	/// RPL_ISON answers with whatever spelling the server prefers, and the
	/// query row follows the peer on and off line from it.
	@Test("An ISON reply matches a query under the server's casemapping")
	func isonReplyFoldsNicknamesTheServersWay() throws {
		let session = session()
		let peerQuery = try query("nick[home]", on: session)

		session.markAsLoggedIn()
		peerQuery.deactivate()
		session.onISONTimer()

		try receive(":irc.example.net 303 me :nick{home}", on: session)

		#expect(peerQuery.isActive)
	}

	/// A poll longer than one ISON draws one reply per command, and each reply
	/// names only who is online among its own nicknames.
	@Test("An ISON reply leaves the nicknames another command asked about alone")
	func isonReplyReconcilesOnlyItsOwnNicknames() throws {
		let session = session()
		let peers = try (1 ... 16).map { try query("peer\($0)", on: session) }

		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.onISONTimer()

		let isonLines = session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("ISON ") }
		try #require(isonLines.count == 2)

		// The first command's reply: peer1 is gone, every other peer is online.
		let firstReply = (2 ... 15).map { "peer\($0)" }.joined(separator: " ")
		try receive(":irc.example.net 303 me :\(firstReply)", on: session)

		#expect(peers[0].isActive == false)
		let middlePeersAreActive = peers[1 ..< 15].allSatisfy(\.isActive)
		#expect(middlePeersAreActive)
		#expect(peers[15].isActive, "peer16 was asked about by the second command")

		try receive(":irc.example.net 303 me :peer16", on: session)

		#expect(peers[15].isActive)
	}

	@Test("A server with MONITOR is not polled with ISON")
	func monitorServerIsNotPolled() throws {
		let session = session()
		_ = try query("peer", on: session)

		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.enableCapability(.monitorCommand)
		session.onISONTimer()

		let sent = session.sentLines.compactMap { $0 as? String }
		#expect(sent.contains { $0.hasPrefix("ISON") } == false)
	}

	// MARK: - Typing

	/// A typing indicator filed under one spelling never cleared when the
	/// `done` tag arrived spelled the other way, so it hung until it expired.
	@Test("A typing indicator is keyed under the server's casemapping")
	func typingIndicatorsFoldTheServersWay() throws {
		let session = session()
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()

		let tracker = session.typingTracker
		tracker.noteTypingState(.active, fromNickname: "nick[home]", in: channel)

		#expect(tracker.typingNicknames(in: channel) == ["nick[home]"])

		tracker.noteTypingState(.done, fromNickname: "NICK{HOME}", in: channel)

		#expect(tracker.typingNicknames(in: channel).isEmpty)
	}

	// MARK: - Rekeying the directory

	/** A `CASEMAPPING` change can merge two keys that used to be distinct. The
	 loser used to be dropped from the directory while its member rows stayed in
	 every channel it was in, where nothing could find or remove them again. */
	@Test("A casemapping change leaves no member row the directory cannot find")
	func casemappingChangeLeavesNoOrphanedMemberRows() throws {
		let session = session()

		try receive(":irc.example.net 005 me CASEMAPPING=ascii :are supported by this server", on: session)

		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()

		try receive(":irc.example.net 353 me = #chan :nick[home] nick{home}", on: session)

		#expect(session.numberOfUsers == 2)
		#expect(channel.numberOfMembers == 2)

		try receive(":irc.example.net 005 me CASEMAPPING=rfc1459 :are supported by this server", on: session)

		#expect(session.numberOfUsers == 1)
		#expect(channel.numberOfMembers == 1)

		let members = try #require(channel.memberInfo).memberList

		for member in members {
			#expect(session.findUser(member.user.nickname) != nil)
			#expect(channel.findMember(member.user.nickname) != nil)
		}
	}

	// MARK: - Nickname collision ceiling

	/** A server that refuses every nickname — a `NICKLEN` the session cannot
	 satisfy, or services holding the whole family of names — used to be
	 answered forever, one NICK per 432/433, until one side gave up on the
	 connection. */
	@Test("Nickname retries stop at the ceiling and say so")
	func nicknameRetriesStopAtTheCeiling() throws {
		let session = session(nickname: "mara")
		session.config.alternateNicknames = ["mara-alt"]
		session.setConnectionTransportForTesting(.connected)

		for _ in 0 ... Int(NicknameRetryPolicy.maximumAttempts) + 3 {
			let collision = try #require(
				Message(line: ":irc.example.net 433 * mara :Nickname is already in use", on: session)
			)

			session.receiveNumericReply(collision)
		}

		#expect(session.sentLines.count == Int(NicknameRetryPolicy.maximumAttempts))

		let bodies = (session.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.filter { $0 == String(localized: .IRC.nicknameRetriesExhausted) }.count == 1)
	}

	/// The count is the retry sequence, and a nickname the session now holds
	/// resolves it — whether the session asked for it or the user did.
	@Test("A nickname that lands resets the retry count")
	func aNicknameThatLandsResetsTheRetryCount() throws {
		let session = session(nickname: "mara")
		session.setConnectionTransportForTesting(.connected)
		session.nicknameRetry.attempt = NicknameRetryPolicy.maximumAttempts

		try receive(":mara!m@example.org NICK mara2", on: session)

		#expect(session.nicknameRetry.attempt == 0)
	}
}
