import Glasstual
import XCTest

/** *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
class IRCExtrasMigrationTests: XCTestCase {
	func testParseIRCProtocolURIRejectsMalformedSlashCounts() {
		/* Too few slashes — should no-op without crashing. */
		XCTAssertNoThrow(IRCExtras.parseIRCProtocolURI("irc:example"))
		/* Too many slashes — should no-op without crashing. */
		XCTAssertNoThrow(IRCExtras.parseIRCProtocolURI("irc://a/b/c/d"))
	}

	func testParseIRCProtocolURIAcceptsBasicIrcURL() {
		/* Parsing only: connection creation is a no-op under XCTest so the
		 host app's saved servers are not mutated and merge prompts are skipped. */
		XCTAssertNoThrow(IRCExtras.parseIRCProtocolURI("irc://irc.example.test/#chat"))
	}
}
