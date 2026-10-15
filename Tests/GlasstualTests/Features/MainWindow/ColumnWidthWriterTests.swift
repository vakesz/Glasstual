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

	private func withStoredWidth(_ width: Double, _ body: () async throws -> Void) async rethrows {
		let stored = key.value
		defer { key.value = stored }
		key.value = width
		try await body()
	}

	@Test("A width that settles back to the stored one writes nothing")
	func settlingBackCancelsWrite() async throws {
		try await withStoredWidth(210) {
			let writer = ColumnWidthWriter(key, settle: .milliseconds(5))
			writer.record(420)
			writer.record(210)
			try await Task.sleep(for: .milliseconds(50))
			#expect(key.value == 210)
		}
	}

	@Test("The width a column rests at is stored once the drag ends")
	func restingWidthIsStored() async throws {
		try await withStoredWidth(210) {
			let writer = ColumnWidthWriter(key, settle: .milliseconds(5))
			writer.record(240)
			writer.record(250)
			#expect(key.value == 210)
			try await Task.sleep(for: .milliseconds(50))
			#expect(key.value == 250)
		}
	}

	@Test("A width outside the column's bounds is ignored")
	func outOfRangeWidthIsIgnored() async throws {
		try await withStoredWidth(210) {
			let writer = ColumnWidthWriter(key, settle: .milliseconds(5))
			writer.record(250)
			writer.record(0)
			try await Task.sleep(for: .milliseconds(50))
			#expect(key.value == 250)
		}
	}
}
