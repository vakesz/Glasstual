// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The command form of the Server Properties, Channel Properties and nickname
 colour editors: `/serverconfig`, `/channelconfig` and `/setcolor` with a
 colour.

 The editors' own models validate and apply what a command changes, so a value
 the sheet refuses the command refuses too, with the sheet's own message. The
 application implements it; the session only reads the line and prints what
 comes back. */
@MainActor
protocol ConfigurationCommanding: AnyObject {
	/// Carries out `/serverconfig <arguments>` on `session` and returns the
	/// lines to print.
	func performServerConfiguration(_ arguments: String, on session: ServerSession) -> [String]
	/// Carries out `/channelconfig <arguments>`; `target` is the conversation
	/// the command was typed in, used when no channel is named.
	func performChannelConfiguration(_ arguments: String, on session: ServerSession, target: Conversation?) -> [String]
	/// Pins `nickname` to a colour, or lets it go back to its own with
	/// `reset`, and returns the lines to print.
	func setNicknameColor(_ value: String, for nickname: String) -> [String]
}
