// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

/** Stores a column's width once the divider has come to rest.

 A width written on every frame of the drag is a defaults write on every
 frame, and a defaults write invalidates every view that reads a setting
 through ``ObservableSettings`` -- the member list among them. The column
 being dragged then lays out again under the pointer, and the divider will
 not follow it. */
@MainActor
final class ColumnWidthWriter {
	private let key: SettingsKey<Double>
	private let settle: Duration
	private var write: Task<Void, Never>?

	init(_ key: SettingsKey<Double>, settle: Duration = .milliseconds(250)) {
		self.key = key
		self.settle = settle
	}

	func record(_ width: CGFloat) {
		let value = Double(width)
		guard key.accepts(value) else { return }
		/* A column passes through other widths while it settles. One that
		 comes back to the stored width leaves nothing to write. */
		write?.cancel()
		guard key.value != value else { return }
		write = Task { [key, settle] in
			try? await Task.sleep(for: settle)
			guard !Task.isCancelled else { return }
			key.value = value
		}
	}
}
