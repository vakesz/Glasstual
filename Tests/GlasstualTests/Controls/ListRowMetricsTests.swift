// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("List row metrics")
struct ListRowMetricsTests {
	@Test("Text, glyphs and avatars grow with the system's sidebar size")
	func scalesWithRowSize() {
		let small = ListRowMetrics(.small)
		let medium = ListRowMetrics(.medium)
		let large = ListRowMetrics(.large)
		#expect(small.textPointSize < medium.textPointSize && medium.textPointSize < large.textPointSize)
		#expect(small.glyphWidth < medium.glyphWidth && medium.glyphWidth < large.glyphWidth)
		#expect(small.avatarSize < medium.avatarSize && medium.avatarSize < large.avatarSize)
		#expect(medium.secondaryPointSize < medium.textPointSize)
	}

	@Test("A table's own default size and a custom height read as medium")
	func defaultIsMedium() {
		#expect(ListRowMetrics.Size(NSTableView.RowSizeStyle.default) == .medium)
		#expect(ListRowMetrics.Size(NSTableView.RowSizeStyle.custom) == .medium)
		#expect(ListRowMetrics.Size(NSTableView.RowSizeStyle.small) == .small)
		#expect(ListRowMetrics.Size(NSTableView.RowSizeStyle.large) == .large)
	}

	@Test("A source list draws its text at the same sizes its own cells use")
	func matchesSourceListText() {
		#expect(ListRowMetrics(.small).textPointSize == NSFont.smallSystemFontSize)
		#expect(ListRowMetrics(.medium).textPointSize == NSFont.systemFontSize)
	}

	@Test("A two-line row fits both lines and is never shorter than a one-line row")
	func twoLineRow() {
		for style in [ListRowMetrics.Size.small, .medium, .large] {
			let metrics = ListRowMetrics(style)
			let title = TextLineMetrics.lineHeight(for: .systemFont(ofSize: metrics.textPointSize))
			let subtitle = TextLineMetrics.lineHeight(for: .systemFont(ofSize: metrics.secondaryPointSize))
			let height = metrics.twoLineRowHeight(oneLineRowHeight: 24)
			#expect(height >= title + subtitle)
			#expect(height >= 24)
			#expect(metrics.twoLineRowHeight(oneLineRowHeight: 80) == 80)
		}
	}

	@Test("An avatar row keeps a margin above and below the avatar")
	func avatarRow() {
		let metrics = ListRowMetrics(.medium)
		#expect(metrics.avatarRowHeight > metrics.avatarSize)
		#expect(ListRowMetrics.sectionRowHeight > TextLineMetrics.lineHeight(for: .preferredFont(forTextStyle: .caption1)))
	}
}
