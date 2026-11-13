// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// ISON and WHO polling for tracked users and away status.
struct PresencePolling {
	let isonTimer: SessionTimer
	let whoTimer: SessionTimer
	/// Builds the ISON watch list a little after registration.
	var populationTask: SessionTimer?
	/// The first ISON reply after registration reports who is there, not who arrived.
	var isFirstISONReply = false
	/// Where the next WHO batch starts in the conversation list.
	var nextWhoConversationIndex: UInt = 0

	mutating func resetForTeardown() {
		isFirstISONReply = false
		nextWhoConversationIndex = 0
	}

	mutating func cancelPopulation() {
		populationTask?.stop()
		populationTask = nil
	}
}
