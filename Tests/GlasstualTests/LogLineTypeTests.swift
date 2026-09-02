/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Log line types")
struct LogLineTypeTests {
	@Test("What a person said is conversation")
	func spokenLinesAreConversation() {
		for type in [LogLineType.privateMessage, .privateMessageNoHighlight, .action, .actionNoHighlight, .notice] {
			#expect(type.isConversation, "\(type)")
		}
	}

	@Test("What the client narrates on join is not")
	func narratedEventsAreNotConversation() {
		for type in [LogLineType.join, .part, .quit, .mode, .topic, .nick, .kick, .debug, .website] {
			#expect(type.isConversation == false, "\(type)")
		}
	}
}
