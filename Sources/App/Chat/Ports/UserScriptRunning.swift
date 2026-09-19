// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The user scripts a typed command can run.

 A command name the session has no handler of its own for is not an error: a user
 script may claim it, and what is left goes to the server as written. The
 protocol layer asks the one question it has — "does a script answer for this?"
 — and hands over the line; where the scripts are, what language they are in and
 how their output comes back is the feature's business. */
@MainActor
protocol UserScriptRunning: AnyObject {
	/// Runs the script `command` names, with the rest of the line as its input
	/// and the conversation it was typed in as its target. `false` when no
	/// script claims the command.
	func runScript(forOutgoingCommand command: String, input: String, target: String?, on session: ServerSession) -> Bool
}
