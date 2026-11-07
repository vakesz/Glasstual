// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Owns the tasks that run a session's scripts off the main actor and bring the
 output back.

 A script that outlives its session has nowhere to report to, so the session
 cancels what is still running when it goes. Each task removes itself when it
 finishes, so the bag holds only scripts still in flight. */
@MainActor
final class ScriptTaskBag {
	private var tasks: [UUID: Task<Void, Never>] = [:]

	func run(_ operation: @escaping @MainActor () async -> Void) {
		let identifier = UUID()
		/* The main actor has not yet started the task when it is stored, so it
		 cannot finish and look for itself before it is there. */
		tasks[identifier] = Task { [weak self] in
			await operation()
			self?.tasks[identifier] = nil
		}
	}

	func cancelAll() {
		let running = tasks.values
		tasks.removeAll()
		for task in running {
			task.cancel()
		}
	}

	isolated deinit {
		cancelAll()
	}
}
