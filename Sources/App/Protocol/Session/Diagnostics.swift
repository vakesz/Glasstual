// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Client {
	func createRawDataLogQuery() {
		guard !isTerminating, rawDataLogQuery == nil,
		      let query = findChannelOrCreate("Server Traffic", isUtility: true)
		else { return }

		rawDataLogQuery = query
		output?.select(query)
		rawDataLog(String(localized: .IRC.serverTrafficWillBeOutput))
	}

	func destroyRawDataLogQuery() {
		guard !isTerminating, let query = rawDataLogQuery else { return }
		clientDirectory?.destroyChannel(query)
	}

	func rawDataLog(_ data: String) {
		guard !isTerminating else { return }
		printDebugInformation(data, in: rawDataLogQuery)
	}

	/** Outgoing traffic is the half that carries the user's credentials —
	 `PASS`, `AUTHENTICATE`, `OPER` and a NickServ `IDENTIFY` all put one on the
	 wire — and this window is a transcript people paste into bug reports, so
	 the secret is masked before it is printed while the command stays legible. */
	func rawDataLogOutgoingTraffic(_ data: String) {
		guard rawDataLogQuery != nil else { return }
		rawDataLog("<< \(WireRedaction.redactedRawLogLine(data))")
	}

	/// Incoming traffic carries them too: `echo-message` sends the client's own
	/// `IDENTIFY` back to it, and a bouncer replays what the client sent. The
	/// source prefix and tags are kept, so the same masking applies.
	func rawDataLogIncomingTraffic(_ data: String) {
		guard rawDataLogQuery != nil else { return }
		rawDataLog(">> \(WireRedaction.redactedRawLogLine(data))")
	}
}

@MainActor
extension Client {
	func removeRequestedCommands() {
		requestedCommands.removeCommands()
	}

	func createHiddenCommandResponses() {
		guard !isTerminating, hiddenCommandResponsesQuery == nil,
		      let query = findChannelOrCreate("Hidden Responses", isUtility: true)
		else { return }

		hiddenCommandResponsesQuery = query
		output?.select(query)
		printDebugInformation(String(localized: .IRC.commandResponsesWhichAreNormallyHidden), in: query)
	}

	func printReplyToHiddenCommandResponsesQuery(_ message: Message) {
		guard let query = hiddenCommandResponsesQuery else { return }
		printReply(message, in: query)
	}
}
