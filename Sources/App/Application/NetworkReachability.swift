// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// Reports connectivity changes after the first path establishes the initial state.
/// Keep this value across monitor restarts to detect changes during sleep.
nonisolated struct NetworkReachability {
	private var isReachable: Bool?

	mutating func update(isReachable: Bool) -> Bool? {
		let previous = self.isReachable
		self.isReachable = isReachable
		guard let previous, previous != isReachable else { return nil }
		return isReachable
	}
}
