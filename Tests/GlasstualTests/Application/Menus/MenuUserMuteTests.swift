// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("User mute menu")
struct MenuUserMuteTests {
	@Test("The local user's messages cannot be muted")
	func localUserCannotBeMuted() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		let channel = try #require(session.findConversationOrCreate("#chat"))
		let controller = MenuActionController()
		controller.context.pointedSession = session
		controller.context.pointedConversation = channel
		let mute = NSMenuItem()
		mute.command = .muteUser
		mute.userInfoString = "ME"

		#expect(controller.validator.validateMemberCommand(mute) == false)
		#expect(controller.context.muteTarget(for: mute) == nil)
		session.setUserMuted(true, nickname: "ME")
		#expect(session.isUserMuted(nickname: "me") == false)
		#expect(session.config.ignoreList.isEmpty)
	}

	@Test("A transcript sender can be muted and unmuted while disconnected")
	func departedTranscriptSenderCanBeMuted() throws {
		let session = TestServerSession()
		let channel = try #require(session.findConversationOrCreate("#chat"))
		let controller = MenuActionController()
		controller.context.pointedSession = session
		controller.context.pointedConversation = channel
		let mute = NSMenuItem()
		mute.command = .muteUser
		mute.userInfoString = "departed"
		let unmute = NSMenuItem()
		unmute.command = .unmuteUser
		unmute.userInfoString = "departed"

		#expect(controller.validator.validateMemberCommand(mute))
		#expect(controller.validator.validateMemberCommand(unmute) == false)
		#expect(unmute.isHidden)
		controller.memberMute(mute)
		#expect(session.isUserMuted(nickname: "departed"))
		#expect(controller.validator.validateMemberCommand(mute) == false)
		#expect(mute.isHidden)
		#expect(controller.validator.validateMemberCommand(unmute))

		controller.memberUnmute(unmute)
		#expect(session.isUserMuted(nickname: "departed") == false)
		#expect(controller.validator.validateMemberCommand(mute))
	}

	@Test("A member without a hostmask can be muted directly")
	func memberWithoutHostmaskCanBeMuted() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		let channel = try #require(session.findConversationOrCreate("#chat"))
		channel.activate()
		let member = Member(user: User(nickname: "alice"), prefixes: session.currentUserPrefixes)
		let controller = MenuActionController()
		controller.context.pointedSession = session
		controller.context.pointedConversation = channel
		let mute = NSMenuItem()
		mute.command = .muteUser

		controller.context.withContext(.members([member])) {
			#expect(controller.validator.validateMemberCommand(mute))
			#expect(controller.context.muteTarget(for: mute)?.nickname == "alice")
		}
	}
}
