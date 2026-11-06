// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Session messages")
struct SessionMessagesTests {
	@Test("A nickname change carries both spellings to observers of that session only")
	func nicknameChangeCarriesBothNicknames() {
		let center = NotificationCenter()
		let session = TestServerSession()
		let otherSession = TestServerSession()
		var received: [ServerSessionNicknameChanged] = []
		let token = center.addObserver(of: session, for: ServerSessionNicknameChanged.self) { message in
			received.append(message)
		}
		defer { center.removeObserver(token) }

		ServerSessionNicknameChanged(subject: otherSession, oldNickname: "x", newNickname: "y").post(on: center)
		ServerSessionNicknameChanged(subject: session, oldNickname: "old", newNickname: "new").post(on: center)

		#expect(received.count == 1)
		#expect(received.first?.subject === session)
		#expect(received.first?.oldNickname == "old")
		#expect(received.first?.newNickname == "new")
	}

	@Test("A nickname change survives the trip through a notification")
	func nicknameChangeRoundTrips() throws {
		let session = TestServerSession()
		let notification = ServerSessionNicknameChanged.makeNotification(
			ServerSessionNicknameChanged(subject: session, oldNickname: "a", newNickname: "b")
		)

		#expect(notification.name == ServerSessionNicknameChanged.name)
		let message = try #require(ServerSessionNicknameChanged.makeMessage(notification))
		#expect(message.oldNickname == "a")
		#expect(message.newNickname == "b")
		#expect(ServerSessionNicknameChanged.makeMessage(Notification(name: .init("other"))) == nil)
	}

	@Test("A typing change names the conversation and its session")
	func typingChangeRoundTrips() throws {
		let session = TestServerSession()
		let conversation = Conversation(config: ConversationConfig(name: "#chat"))
		let notification = TypingTrackerDidChange.makeNotification(
			TypingTrackerDidChange(subject: session, conversation: conversation)
		)

		let message = try #require(TypingTrackerDidChange.makeMessage(notification))
		#expect(message.subject === session)
		#expect(message.conversation === conversation)
	}

	@Test("A lifecycle message is delivered inline to observers of its session")
	func lifecycleMessageIsDeliveredInline() {
		let center = NotificationCenter()
		let session = TestServerSession()
		var count = 0
		let token = center.addObserver(of: session, for: ServerSessionDidConnect.self) { message in
			#expect(message.subject === session)
			count += 1
		}
		defer { center.removeObserver(token) }

		ServerSessionDidConnect(subject: session).post(on: center)
		ServerSessionDidConnect(subject: TestServerSession()).post(on: center)

		#expect(count == 1)
	}
}
