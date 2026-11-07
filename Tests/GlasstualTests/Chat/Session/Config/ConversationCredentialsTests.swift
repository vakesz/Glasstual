// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Conversation credentials", .timeLimit(.minutes(1)))
struct ConversationCredentialsTests {
	private enum Change: CaseIterable {
		case none, disconnected, reconnected, removed, replaced, edited, quitting, terminating
	}

	@Test("Channel credentials belong to the connection and conversation that requested them", arguments: Change.allCases)
	private func lateLookupRespectsOwnership(_ change: Change) async throws {
		let session = TestServerSession()
		let conversation = try #require(session.findConversationOrCreate("#secret"))
		let item = conversation.config.keychainItem
		session.setConnectionTransportForTesting(.connected)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		defer {
			session.cancelPendingSessionTasks()
			release.finish()
			didStart.finish()
		}
		session.credentialLoader = { _ in
			didStart.yield(())
			for await _ in gate {}
			return [item: "loaded"]
		}
		session.resolveSecretKey(for: conversation)
		let lookup = try #require(session.startup.channelCredentialTasks[item])
		var events = started.makeAsyncIterator()
		_ = await events.next()
		switch change {
		case .none: break
		case .disconnected: session.disconnect()
		case .reconnected: session.startup = StartupState()
		case .removed: session.remove(conversation)
		case .replaced:
			session.remove(conversation)
			let replacement = Conversation(config: conversation.config)
			replacement.associatedSession = session
			session.add(replacement)
		case .edited: session.sessionCredentials.apply([item: .set("edited")])
		case .quitting: session.connectionState.beginQuit()
		case .terminating: session.isTerminating = true
		}
		release.finish()
		await lookup.value

		let expected: String? = switch change {
		case .none: "loaded"
		case .edited: "edited"
		default: nil
		}
		#expect(session.sessionCredentials.password(for: item) == expected)
		#expect(session.sessionCredentials.hasResolved(item) == (expected != nil))
		#expect(session.startup.channelCredentialTasks.isEmpty)
	}
}
