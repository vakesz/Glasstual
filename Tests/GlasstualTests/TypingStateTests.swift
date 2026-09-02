/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Typing state")
@MainActor
struct TypingStateTests {
	/// The states go on the wire as the `+typing` tag value, so their spellings
	/// are part of the protocol.
	@Test("Each state keeps the spelling IRCv3 gives it")
	func matchesTheWireSpelling() {
		#expect(TypingState.active.rawValue == "active")
		#expect(TypingState.paused.rawValue == "paused")
		#expect(TypingState.done.rawValue == "done")
		#expect(TypingState(rawValue: "typing") == nil)
	}

	@Test("An active notification is sent again only once the interval is up")
	func rateLimitsTheActiveNotification() {
		let now = Date(timeIntervalSince1970: 100)

		#expect(OutboundTypingPolicy.shouldSendActive(previousState: nil, lastSentAt: nil, now: now))
		#expect(OutboundTypingPolicy.shouldSendActive(previousState: .paused, lastSentAt: now, now: now))
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-OutboundTypingPolicy.activeInterval),
			now: now
		))
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now,
			now: now
		) == false)
	}
}
