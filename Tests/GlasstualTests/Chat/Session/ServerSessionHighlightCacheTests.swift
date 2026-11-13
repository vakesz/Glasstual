// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server session highlight cache")
struct ServerSessionHighlightCacheTests {
	private func makeSession() -> TestServerSession {
		var settings = ChatSettings()
		settings.logHighlights = true

		return TestServerSession(
			configDictionary: [:],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
	}

	private func makeChannel(on session: ServerSession) -> Conversation {
		let channel = Conversation(config: ConversationConfig(name: "#chat", type: .channel))
		channel.associatedSession = session

		return channel
	}

	private func chatLine(_ body: String) -> ChatLine {
		var line = ChatLine()
		line.messageBody = body
		line.nickname = "alice"
		line.lineType = .privateMessage

		return line
	}

	@Test("A logged highlight is offered to the window, not to a sheet the session reached for")
	func aCachedHighlightIsReportedThroughTheOutputSeam() {
		let session = makeSession()
		let channel = makeChannel(on: session)

		session.cacheHighlight(in: channel, with: chatLine("hello"))

		#expect(session.cachedHighlights.count == 1)
		#expect(session.recordedOutput.loggedHighlights.map(\.lineLogged.messageBody) == ["hello"])
	}

	@Test("Highlights are not cached when the preference is off")
	func highlightsAreNotCachedWhenLoggingIsOff() {
		let session = TestServerSession(
			configDictionary: [:],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
		let channel = makeChannel(on: session)

		session.cacheHighlight(in: channel, with: chatLine("hello"))

		#expect(session.cachedHighlights.isEmpty)
		#expect(session.recordedOutput.loggedHighlights.isEmpty)
	}

	/// The cache used to grow for the life of the session, holding every
	/// `ChatLine` it ever matched.
	@Test("The cache stops at its ceiling and drops the oldest highlights")
	func theCacheIsBounded() {
		let session = makeSession()
		let channel = makeChannel(on: session)
		let overflow = 10

		for index in 0 ..< (ServerSession.maximumCachedHighlights + overflow) {
			session.cacheHighlight(in: channel, with: chatLine("\(index)"))
		}

		#expect(session.cachedHighlights.count == ServerSession.maximumCachedHighlights)
		#expect(session.cachedHighlights.first?.lineLogged.messageBody == "\(overflow)")
		#expect(
			session.cachedHighlights.last?.lineLogged.messageBody
				== "\(ServerSession.maximumCachedHighlights + overflow - 1)"
		)
	}
}
