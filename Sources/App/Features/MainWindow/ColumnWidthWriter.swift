// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics
import Foundation

/** Stores a column's width once the divider has come to rest.

 A width written on every frame of the drag is a defaults write on every
 frame, and a defaults write invalidates every view that reads a setting
 through ``ObservableSettings`` -- the member list among them. The column
 being dragged then lays out again under the pointer, and the divider will
 not follow it. */
@MainActor
final class ColumnWidthWriter {
	private let key: SettingsKey<Double>
	private let settle: TimeInterval
	private let clock: TimerClock
	private var timer: SessionTimer?
	private var pendingWidth: Double?

	init(_ key: SettingsKey<Double>, settle: TimeInterval = 0.25, clock: TimerClock = .continuous) {
		self.key = key
		self.settle = settle
		self.clock = clock
	}

	func record(_ width: CGFloat) {
		let value = Double(width)
		guard key.accepts(value) else { return }
		/* A column passes through other widths while it settles. One that
		 comes back to the stored width leaves nothing to write. */
		timer?.stop()
		pendingWidth = nil
		guard key.value != value else { return }
		pendingWidth = value
		let timer = timer ?? SessionTimer(clock: clock) { [weak self] _ in
			self?.commit()
		}
		self.timer = timer
		timer.start(settle)
	}

	private func commit() {
		guard let width = pendingWidth else { return }
		pendingWidth = nil
		key.value = width
	}
}
