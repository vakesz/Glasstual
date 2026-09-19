// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import QuartzCore
import SwiftUI
import Testing

@MainActor
@Suite("Rendered public-channel fixtures", .serialized, .timeLimit(.minutes(1)))
struct ServerChannelListRenderedFixtureTests {
	@Test("A 20,000-channel window renders long formatted topics at narrow and wide sizes", arguments: [600, 960], [false, true])
	func renderLargeChannelList(width: Int, dark: Bool) async throws {
		let model = ServerChannelListModel()
		let topics = [
			"\u{2}Swift and AppKit\u{2} — public discussion, documentation, and community support",
			"\u{3}04Red\u{f}, \u{3}03green\u{f}, \u{1f}underlined\u{1f} and \u{1d}italic\u{1d} IRC topics",
			String(repeating: "Árvíztűrő tükörfúrógép · Übertragung · 👩🏽‍💻 · ", count: 12),
		]
		for index in 0 ..< ServerChannelListModel.maximumEntryCount {
			model.enqueue(
				channelName: index.isMultiple(of: 3) ? "#a-very-long-public-channel-name-\(index)" : "#channel-\(index)",
				memberCount: UInt(ServerChannelListModel.maximumEntryCount - index),
				topic: topics[index % topics.count]
			)
		}
		model.finishRefresh()
		for await filtering in Observations({ model.isFiltering }) where filtering == false {
			break
		}
		model.selection = Set(model.rows.prefix(2).map(\.id))
		model.minimumUserCount = "12"
		let root = ServerChannelListView(model: model, supportsMinimumUserCount: true, joinSelected: {}, update: {})
			.background(Color(nsColor: .windowBackgroundColor))
			.frame(width: CGFloat(width), height: 540)
		let host = NSHostingView(rootView: root)
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 540),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		window.contentView = host
		// A never-ordered window can omit AppKit backing layers from a SwiftUI
		// capture. Realize only this disposable window, behind and off screen.
		window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		window.order(.below, relativeTo: 0)
		host.layoutSubtreeIfNeeded()
		let table = try #require(descendantTable(in: host))
		table.layoutSubtreeIfNeeded()
		let cell = try #require(table.view(atColumn: 0, row: 3, makeIfNecessary: true) as? ServerChannelListTableCell)
		cell.layoutSubtreeIfNeeded()
		let label = try #require(cell.textField)
		#expect(label.stringValue == model.rows[3].channelName)
		#expect(label.font?.fontDescriptor.symbolicTraits.contains(.bold) == false)
		let countCell = try #require(table.view(atColumn: 1, row: 3, makeIfNecessary: true) as? ServerChannelListTableCell)
		#expect(countCell.textField?.font?.fontDescriptor.symbolicTraits.contains(.bold) == false)
		#expect(label.frame.width > 0 && label.frame.height > 0)
		#expect(cell.bounds.contains(label.frame))
		#expect(table.numberOfRows == ServerChannelListModel.maximumEntryCount)
		#expect(table.tableColumns.count == 3)
		#expect(table.selectedRowIndexes == IndexSet([0, 1]))
		#expect(table.accessibilityLabel() == String(localized: .ServerChannelList.publicChannelList))
		let scrollView = try #require(table.enclosingScrollView)
		#expect(scrollView.frame.width <= host.frame.width)
		#expect(scrollView.frame.height < host.frame.height)
		var visibleRows = 0
		table.enumerateAvailableRowViews { _, _ in visibleRows += 1 }
		#expect(visibleRows > 0 && visibleRows < 100)
		window.displayIfNeeded()
		CATransaction.flush()
		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		#expect(containsVisibleText(in: label, host: host, bitmap: bitmap), "The image must contain channel text below the header")
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		#expect(png.count > 1000)
		let support = try #require(ApplicationPaths.applicationSupportURL)
		let directory = support.appendingPathComponent("review-fixtures", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let appearance = dark ? "dark" : "light"
		try png.write(to: directory.appendingPathComponent("channels-20000-\(width)-\(appearance).png"), options: .atomic)
	}

	/// This unselected text field has a flat background. Checking its pixels
	/// catches blank backing layers even when AppKit reports populated rows.
	private func containsVisibleText(in label: NSTextField, host: NSView, bitmap: NSBitmapImageRep) -> Bool {
		let rect = label.convert(label.bounds, to: host)
		let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
		let top = host.isFlipped ? rect.minY : host.bounds.maxY - rect.maxY
		let left = max(0, Int(rect.minX * scale))
		let right = min(bitmap.pixelsWide, Int(rect.maxX * scale))
		let firstRow = max(0, Int(top * scale))
		let lastRow = min(bitmap.pixelsHigh, Int((top + rect.height) * scale))
		guard left < right, firstRow < lastRow else { return false }
		var minimum = CGFloat(1)
		var maximum = CGFloat(0)
		for y in firstRow ..< lastRow {
			for x in left ..< right {
				guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
				let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
				minimum = min(minimum, brightness)
				maximum = max(maximum, brightness)
			}
		}
		return maximum - minimum > 0.2
	}

	private func descendantTable(in view: NSView) -> ServerChannelListNativeTable? {
		if let table = view as? ServerChannelListNativeTable {
			return table
		}
		for child in view.subviews {
			if let table = descendantTable(in: child) {
				return table
			}
		}
		return nil
	}
}
