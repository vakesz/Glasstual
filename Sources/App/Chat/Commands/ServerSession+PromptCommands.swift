// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	/** Refuses an answer to a question that did not come from the message field.

	 `/answer`, `/yes`, `/no`, `/prompts` and the answering `/dcc` subcommands
	 are read by the window before a typed line reaches the session. One that
	 arrives here came from a script, a timer, a connect command or an alias,
	 and none of those may answer a question on the reader's behalf. */
	func refuseUntypedPromptAnswer() {
		printDebugInformation(String(localized: .IRC.promptAnswerTypedOnly))
	}
}
