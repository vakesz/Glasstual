// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// A column reports every width it passes through while it settles; only the
/// one it comes to rest at may reach the stored setting.
@Suite("Column width writer")
@MainActor
struct ColumnWidthWriterTests {
	private let key = SettingsKeys.MainWindow.memberListWidth

	private func withStoredWidth(_ width: Double, _ body: () async -> Void) async {
		let stored = key.value
		defer { key.value = stored }
		key.value = width
		await body()
	}

	@Test("A width that settles back to the stored one writes nothing")
	func settlingBackCancelsWrite() async {
		await withStoredWidth(210) {
			let clock = ManualTimerClock()
			defer { clock.finish() }
			let writer = ColumnWidthWriter(key, settle: 0.25, clock: clock.timerClock)
			writer.record(420)
			writer.record(210)
			await clock.advance(by: 0.3)
			#expect(key.value == 210)
		}
	}

	@Test("The width a column rests at is stored once the drag ends")
	func restingWidthIsStored() async {
		await withStoredWidth(210) {
			let clock = ManualTimerClock()
			defer { clock.finish() }
			let writer = ColumnWidthWriter(key, settle: 0.25, clock: clock.timerClock)
			writer.record(240)
			writer.record(250)
			#expect(key.value == 210)
			await clock.advance(by: 0.1)
			#expect(key.value == 210)
			await clock.advance(by: 0.3)
			#expect(key.value == 250)
		}
	}

	@Test("A width outside the column's bounds is ignored")
	func outOfRangeWidthIsIgnored() async {
		await withStoredWidth(210) {
			let clock = ManualTimerClock()
			defer { clock.finish() }
			let writer = ColumnWidthWriter(key, settle: 0.25, clock: clock.timerClock)
			writer.record(250)
			writer.record(0)
			await clock.advance(by: 0.3)
			#expect(key.value == 250)
		}
	}
}
