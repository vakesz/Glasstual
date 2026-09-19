// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/** Whether a refusal may be shown yet.

 A sheet opens on fields nobody has typed into, and a new rule opens on an empty
 keyword: saying so before anything was typed is not a refusal, it is a
 complaint about something the person has not done yet. So every editor keeps
 what is wrong with its value separately from whether that has been said out
 loud, and only the first refused save turns the messages on. */
struct SubmissionGate {
	/// Whether saving has been tried at least once.
	private(set) var wasAttempted = false

	/// Records a save attempt; from here on the editor shows what is wrong.
	mutating func attempt() {
		wasAttempted = true
	}

	/// `fault` once saving has been tried, and nothing before that.
	func shown<Fault>(_ fault: Fault?) -> Fault? {
		wasAttempted ? fault : nil
	}

	/// Starts over on a value nobody has edited, such as an editor reloaded
	/// from a configuration that changed underneath it.
	mutating func reset() {
		wasAttempted = false
	}
}
