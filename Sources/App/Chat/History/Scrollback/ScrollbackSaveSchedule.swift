// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// When the scrollback store saves on its own.
nonisolated struct ScrollbackSaveSchedule {
	struct BurstSave {
		let identifier: UUID
		let task: Task<Void, Never>
	}

	/// How long the store waits between the saves it makes on its own. Writes
	/// arm earlier ones; this loop is the safety net for changes they do not
	/// count, such as a replacement or a redaction.
	let saveInterval: Duration
	/** Unsaved rows are about 1.4 KB each in Core Data's registered objects, so
	 500 of them hold the pending cost to roughly 0.7 MB, and a save of that many
	 rows in WAL mode is a few milliseconds. */
	let saveRowThreshold: Int
	/// The longest a written row waits for a save while traffic continues.
	let saveDelay: Duration
	/** The save armed by the rows written since the last one. It waits
	 `saveDelay` from the first of them, or runs at once when `saveRowThreshold`
	 of them have piled up. */
	private(set) var burstSave: BurstSave?
	/** Rows inserted since a save was last attempted, whether or not it landed.
	 Counted from the attempt rather than the success, so a save that keeps
	 failing is retried when the next batch of rows or the next delay is up and
	 not on every row. */
	private var rowsSinceSave = 0

	init(saveInterval: Duration, saveRowThreshold: Int, saveDelay: Duration) {
		self.saveInterval = saveInterval
		self.saveRowThreshold = max(1, saveRowThreshold)
		self.saveDelay = saveDelay
	}

	/// Counts a written row and returns how long until the save it is owed, or
	/// nil when one already armed covers it.
	mutating func noteInsertedRow() -> Duration? {
		rowsSinceSave += 1
		if rowsSinceSave >= saveRowThreshold {
			return .zero
		}
		return burstSave == nil ? saveDelay : nil
	}

	mutating func noteSaveAttempt() {
		rowsSinceSave = 0
	}

	/// Replaces the armed save. The caller has cancelled the one it replaces.
	mutating func arm(_ burst: BurstSave) {
		burstSave = burst
	}

	/// Clears the armed save if it is `identifier`, so it may run.
	mutating func takeBurst(_ identifier: UUID) -> Bool {
		guard burstSave?.identifier == identifier else { return false }
		burstSave = nil
		return true
	}

	mutating func cancel() {
		burstSave?.task.cancel()
		burstSave = nil
	}
}
