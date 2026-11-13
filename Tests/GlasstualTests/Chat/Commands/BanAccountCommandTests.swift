// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `/banaccount` bans the services account a member is logged in to, written
/// with the extended-ban name the server announced in `ACCOUNTEXTBAN`.
@MainActor
@Suite("/banaccount")
struct BanAccountCommandTests {
	private func session(isupport: String = "EXTBAN=~,a ACCOUNTEXTBAN=account") -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData(isupport)
		return session
	}

	private func channel(on session: TestServerSession, member nickname: String, account: String?) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()
		session.modify(session.findUserOrCreate(nickname)) { $0.account = account }
		channel.addUser(session.findUserOrCreate(nickname))
		session.recordedOutput.selectedSession = session
		session.recordedOutput.selectedConversation = channel
		return channel
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}

	private func debugLines(of session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("The member's account is banned with the announced extban name")
	func bansTheAccount() throws {
		let session = session()
		_ = try channel(on: session, member: "alice", account: "alice-acct")

		session.sendCommand("banaccount alice", completeTarget: true, target: "#chan")

		#expect(sentLines(of: session) == ["MODE #chan +b ~account:alice-acct"])
	}

	@Test("A channel named first is the target")
	func channelCanBeNamed() throws {
		let session = session()
		_ = try channel(on: session, member: "alice", account: "alice-acct")

		session.sendCommand("banaccount #chan alice", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["MODE #chan +b ~account:alice-acct"])
	}

	@Test("A member whose account is not known is not banned")
	func unknownAccountIsRefused() throws {
		let session = session()
		_ = try channel(on: session, member: "alice", account: nil)

		session.sendCommand("banaccount alice", completeTarget: true, target: "#chan")

		#expect(sentLines(of: session).isEmpty)
		#expect(debugLines(of: session).contains { $0.contains("alice") })
	}

	@Test("A server that does not announce account bans is not asked for one")
	func unsupportedServerIsRefused() throws {
		let session = session(isupport: "EXTBAN=~,a")
		_ = try channel(on: session, member: "alice", account: "alice-acct")

		session.sendCommand("banaccount alice", completeTarget: true, target: "#chan")

		#expect(sentLines(of: session).isEmpty)
		#expect(debugLines(of: session).count == 1)
	}

	@Test("The command is a moderation command with the same syntax as /ban")
	func commandIsRegistered() {
		#expect(LocalCommand.banaccount.group == .moderation)
		#expect(LocalCommand.banaccount.arguments == LocalCommand.ban.arguments)
		#expect(SlashCommandHelp.byCommand[.banaccount] != nil)
		#expect(MemberModerationCommand.banAccount("Alice") == "banaccount Alice")
	}
}
