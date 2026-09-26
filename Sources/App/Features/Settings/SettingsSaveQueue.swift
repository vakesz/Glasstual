// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The editor saves the application must not quit out from under.

 A Server or Conversation Properties save is accepted long before it is finished: it
 waits on a certificate reference, then on the credential writer, then commits
 the configuration. Quit waits here before it closes any editor or session, and
 a save that failed keeps the editor open rather than letting the application
 go. */
@MainActor
final class SettingsSaveQueue {
	private var saves: [UUID: Task<Void, Never>] = [:]
	/// Changes whenever a save reports failure, so a waiter that started before
	/// one can tell that it happened.
	private var failure = UUID()

	var hasPendingSaves: Bool {
		!saves.isEmpty
	}

	/// Owns an accepted editor save from preparation to commit.
	func submit(_ operation: @escaping @MainActor () async -> Bool) -> Task<Void, Never> {
		let identifier = UUID()
		let task = Task {
			let succeeded = await operation()
			if !succeeded {
				failure = UUID()
			}
			saves[identifier] = nil
		}
		saves[identifier] = task
		return task
	}

	/// Includes saves accepted while an earlier save is still suspended. A
	/// failure leaves the editor open and prevents irreversible quit teardown.
	func waitForSaves() -> Task<Bool, Never> {
		let previousFailure = failure
		return Task {
			while !saves.isEmpty {
				for task in Array(saves.values) {
					await task.value
				}
			}
			return previousFailure == failure
		}
	}
}
