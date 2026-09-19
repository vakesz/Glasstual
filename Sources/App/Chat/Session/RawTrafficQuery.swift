// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The "Server Traffic" window: every line this connection reads or writes.

 A diagnostic transcript people paste into bug reports, so what is printed is
 the wire line with its credentials masked. */
extension ServerSession {
	func createRawDataLogConsole() {
		guard !isTerminating, rawDataLogConsole == nil,
		      let console = findConversationOrCreate("Server Traffic", isConsole: true)
		else { return }

		rawDataLogConsole = console
		output?.select(console)
		rawDataLog(String(localized: .IRC.serverTrafficWillBeOutput))
	}

	func destroyRawDataLogConsole() {
		guard !isTerminating, let console = rawDataLogConsole else { return }
		chatSession?.destroyConversation(console)
	}

	func rawDataLog(_ data: String) {
		guard !isTerminating else { return }
		printDebugInformation(data, in: rawDataLogConsole)
	}

	/** Outgoing traffic is the half that carries the user's credentials —
	 `PASS`, `AUTHENTICATE`, `OPER` and a NickServ `IDENTIFY` all put one on the
	 wire — and this window is a transcript people paste into bug reports, so
	 the secret is masked before it is printed while the command stays legible. */
	func rawDataLogOutgoingTraffic(_ data: String) {
		guard rawDataLogConsole != nil else { return }
		rawDataLog("<< \(WireRedaction.redactedRawChatLine(data))")
	}

	/// Incoming traffic carries them too: `echo-message` sends the session's own
	/// `IDENTIFY` back to it, and a bouncer replays what the session sent. The
	/// source prefix and tags are kept, so the same masking applies.
	func rawDataLogIncomingTraffic(_ data: String) {
		guard rawDataLogConsole != nil else { return }
		rawDataLog(">> \(WireRedaction.redactedRawChatLine(data))")
	}
}
