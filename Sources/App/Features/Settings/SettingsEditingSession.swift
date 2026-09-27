// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Completes the pending Settings field even when quit leaves its window open.
@MainActor
final class SettingsEditingSession {
	private var pending: (identifier: UUID, finish: () -> Void)?

	/// Editing another field first completes the previous one. Repeated edits
	/// in the same field replace its completion with the current binding.
	func track(_ identifier: UUID, finish: @escaping () -> Void) {
		if pending?.identifier != identifier {
			finishEditing()
		}
		pending = (identifier, finish)
	}

	/// A delayed blur or removal only completes the field it belongs to.
	func finishEditing(for identifier: UUID? = nil) {
		guard let pending, identifier == nil || pending.identifier == identifier else { return }
		self.pending = nil
		pending.finish()
	}
}
