// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("User muting")
struct UserMuteTests {
	@Test("Muting a departed sender works without a known hostmask and can be undone")
	func muteWithoutMembership() throws {
		let session = TestServerSession()
		#expect(session.findUser("alice") == nil)
		#expect(session.isUserMuted(nickname: "alice") == false)

		session.setUserMuted(true, nickname: "alice")
		session.setUserMuted(true, nickname: "ALICE")

		let entry = try #require(session.config.ignoreList.first)
		#expect(session.config.ignoreList.count == 1)
		#expect(entry.muteMessages)
		#expect(entry.ignoresEvents == false)
		#expect(session.isUserMuted(nickname: "ALICE"))
		#expect(session.isUserMuted(nickname: "bob") == false)
		#expect(session.findIgnores(forHostmask: "alice!user@example.test").isEmpty)

		session.setUserMuted(false, nickname: "alice")

		#expect(session.config.ignoreList.isEmpty)
		#expect(session.isUserMuted(nickname: "alice") == false)
	}

	@Test("Quick mute follows a literal nickname without muting others on its host")
	func muteMatchesOnlyItsNickname() {
		let session = TestServerSession()
		var user = User(nickname: #"alice\home"#)
		user.username = "shared"
		user.address = "gateway.example.test"
		session.add(user)

		session.setUserMuted(true, nickname: user.nickname)

		#expect(session.isUserMuted(nickname: user.nickname))
		#expect(session.isUserMuted(nickname: "alice|home"))
		#expect(session.findAddressBookEntry(forHostmask: "bob!shared@gateway.example.test") == nil)
		session.remove(user)
		#expect(session.isUserMuted(nickname: user.nickname))
	}

	@Test("Mute respects each server's nickname equivalence", arguments: [
		("ascii", "nick[home]", "nick{home}", false),
		("ascii", #"nick\home"#, "nick|home", false),
		("strict-rfc1459", "nick[home]", "nick{home}", true),
		("strict-rfc1459", "nick~home", "nick^home", false),
		("rfc1459", "nick~home", "nick^home", true),
		("rfc7613", "nick[home]", "nick{home}", false),
		("rfc7613", "Álice", "a\u{301}lice", true),
		("rfc7613", "a\u{301}lice", "ÁLICE", true),
		("rfc7613", "İpek", "i\u{307}pek", true),
	])
	func serverCaseMapping(mapping: String, nickname: String, other: String, sameUser: Bool) {
		let session = TestServerSession()
		session.apply(session.supportInfo.processConfigurationData("CASEMAPPING=\(mapping)"))
		session.setUserMuted(true, nickname: nickname)

		#expect(session.isUserMuted(nickname: other) == sameUser)
		session.setUserMuted(false, nickname: other)
		#expect(session.isUserMuted(nickname: nickname) == !sameUser)
	}

	@Test("Unmuting preserves independently configured ignore rules")
	func unmutePreservesIgnoreRules() throws {
		let session = TestServerSession()
		var rule = AddressBookEntry(hostmask: "alice!*@*")
		rule.ignoreFileTransferRequests = true
		rule.muteMessages = true
		var configuration = session.config
		configuration.ignoreList = [rule]
		session.updateConfig(configuration)

		session.setUserMuted(false, nickname: "alice")

		let saved = try #require(session.config.ignoreList.first)
		#expect(saved.uniqueIdentifier == rule.uniqueIdentifier)
		#expect(saved.ignoreFileTransferRequests)
		#expect(saved.muteMessages == false)
	}

	@Test("Mute survives a settings round trip and legacy entries stay unmuted")
	func mutePersists() throws {
		var muted = AddressBookEntry(hostmask: "alice!*@*")
		muted.muteMessages = true
		let restored = try PropertyListDecoder().decode(AddressBookEntry.self, from: PropertyListEncoder().encode(muted))
		let legacy = try #require(PropertyListModel.decode(AddressBookEntry.self, from: ["hostmask": "alice!*@*"]))

		#expect(restored == muted)
		#expect(restored.muteMessages)
		#expect(legacy.muteMessages == false)
	}

	@Test("Mute is preserved when matching address book rules merge")
	func muteMergesWithTracking() throws {
		let session = TestServerSession()
		var tracking = AddressBookEntry.newUserTrackingEntry()
		tracking.hostmask = "alice"
		var configuration = session.config
		configuration.ignoreList = [tracking]
		session.updateConfig(configuration)
		session.setUserMuted(true, nickname: "alice")

		let combined = try #require(session.findAddressBookEntry(forHostmask: "alice!u@host"))
		#expect(combined.muteMessages)
		#expect(combined.trackUserActivity)
		#expect(session.findIgnores(forHostmask: "alice!u@host").isEmpty)

		session.setUserMuted(false, nickname: "alice")
		#expect(session.config.ignoreList == [tracking])
	}

	@Test("Muted public and private messages still reach transcript delivery", arguments: ["#chat", "me"])
	func incomingMutedMessagesAreRetained(target: String) throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		_ = try #require(session.findConversationOrCreate("#chat"))
		session.setUserMuted(true, nickname: "alice")
		let message = try #require(Message(line: ":alice!user@host PRIVMSG \(target) :retained message", on: session))

		session.receivePrivmsgAndNotice(message)

		let printed = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(printed.contains("retained message"))
	}

	@Test("Mute prevents alerts and unmute restores them")
	func muteSuppressesNotifications() throws {
		var settings = ChatSettings()
		settings.notifyAboutMentions = true
		let fixture = ChatEnvironmentFixture(settings: settings)
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let channel = try #require(session.findConversationOrCreate("#chat"))
		session.setUserMuted(true, nickname: "alice")

		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hello")
		#expect(fixture.notifications.posted.isEmpty)
		#expect(fixture.notifications.attentionRequests == 0)
		#expect(fixture.notifications.claimedThreads.isEmpty)

		session.setUserMuted(false, nickname: "alice")
		session.notifyEvent(.highlight, lineType: .privateMessage, target: channel, nickname: "alice", text: "hello")
		#expect(fixture.notifications.posted.count == 1)
	}
}
