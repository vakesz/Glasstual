/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Main-window typing redirection")
struct MainWindowTypingRedirectPolicyTests {
	@Test("Printable text typed in a sidebar is redirected to the message input")
	func printableTextIsRedirected() {
		#expect(
			MainWindowTypingRedirectPolicy.text(
				for: "Å",
				commandIsPressed: false,
				controlIsPressed: false
			) == "Å"
		)
	}

	@Test("Commands and navigation control characters stay with the sidebar")
	func commandsAndControlsAreNotRedirected() {
		#expect(
			MainWindowTypingRedirectPolicy.text(
				for: "f",
				commandIsPressed: true,
				controlIsPressed: false
			) == nil
		)
		#expect(
			MainWindowTypingRedirectPolicy.text(
				for: "\t",
				commandIsPressed: false,
				controlIsPressed: false
			) == nil
		)
	}
}
