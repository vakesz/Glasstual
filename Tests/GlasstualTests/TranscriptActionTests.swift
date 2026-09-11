/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript click targets")
struct TranscriptActionTests {
	@Test("A transcript action survives the trip through the text storage")
	func actionRoundTrips() {
		for action in [TranscriptAction.nickname("alice"), .channel("#glasstual")] {
			#expect(TranscriptAction(attributeValue: action.attributeValue) == action)
		}
		#expect(TranscriptAction(attributeValue: nil) == nil)
		#expect(TranscriptAction(attributeValue: "something:else") == nil)
	}

	@Test("A reaction chip target survives the trip through the text storage")
	func reactionTargetRoundTrips() {
		let target = TranscriptReactionTarget(messageIdentifier: "msg-1", emoji: "\u{1F44D}")
		#expect(TranscriptReactionTarget(attributeValue: target.attributeValue) == target)
		#expect(TranscriptReactionTarget(attributeValue: nil) == nil)
		#expect(TranscriptReactionTarget(attributeValue: "no-separator") == nil)
	}
}
