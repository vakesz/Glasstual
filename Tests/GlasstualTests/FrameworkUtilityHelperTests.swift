/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import CryptoKit
import Foundation
import Testing

@Suite("Framework utility helpers")
@MainActor
struct FrameworkUtilityHelperTests {
	@Test("Digests render as lowercase hex of the published length")
	func digestsRenderAsHex() {
		let source = Data("abc".utf8) as NSData

		#expect(source.textualSha1 == "a9993e364706816aba3e25717850c26c9cd0d89d")
		#expect(source.textualSha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
		#expect(source.textualSha512 == "ddaf35a193617abacc417349ae204131" +
			"12e6fa4e89a97ea20a9eeee64b55d39a" +
			"2192992a274fc1a836ba3c23a3feebbd" +
			"454d4423643ce80e2a9ac94fa54ca49f")
	}

	@Test("A zero byte keeps both of its hex digits")
	func digestsPadLowBytes() {
		#expect((Data([0x00, 0x0F, 0xF0]) as NSData).textualSha1.count == 40)
		#expect((Data() as NSData).textualSha256 ==
			"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	}

	@Test("A byte count is formatted with a padded fraction")
	func byteCountsAreFormatted() {
		#expect(Int64(0).textualPaddedByteCountDescription.isEmpty == false)
		#expect(Int64(1_500_000).textualPaddedByteCountDescription.contains("MB"))
	}

	@Test("A one-digit number gains a leading zero")
	func integersGainALeadingZero() {
		#expect(NSNumber(value: 7).textualIntegerStringValueWithLeadingZero == "07")
		#expect(NSNumber(value: 42).textualIntegerStringValueWithLeadingZero == "42")
		#expect(NSNumber(value: 1234).textualIntegerStringValueWithLeadingZero == "1234")
	}

	@Test("File operation options are a real OptionSet, not magic numbers")
	func fileOperationOptionsCompose() {
		let options: FileOperationOptions = [.moveToTrash, .removeIfExists]

		#expect(options.contains(.moveToTrash))
		#expect(options.contains(.removeIfExists))
		#expect(options.contains(.symlinkPackages) == false)
		#expect(FileOperationOptions([]).contains(.removeIfExists) == false)
	}

	@Test("Replacing an item refuses a non-file URL rather than reporting success")
	func replacingRejectsNonFileURLs() throws {
		let remote = try #require(URL(string: "https://example.test/theme"))
		let local = FileManager.default.temporaryDirectory.appendingPathComponent("glasstual-test")

		#expect(FileManager.default.replaceItem(at: local, withItemAt: remote) == false)
		#expect(FileManager.default.replaceItem(at: remote, withItemAt: local) == false)
	}

	@Test("An existing destination is not silently reported as replaced")
	func existingDestinationWithoutRemovalFails() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("glasstual-replace-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try Data("a".utf8).write(to: source)
		try Data("b".utf8).write(to: destination)

		#expect(FileManager.default.replaceItem(at: destination, withItemAt: source, options: []) == false)
		#expect(try Data(contentsOf: destination) == Data("b".utf8))

		#expect(FileManager.default.replaceItem(
			at: destination,
			withItemAt: source,
			options: .removeIfExists
		))
		#expect(try Data(contentsOf: destination) == Data("a".utf8))
	}

	@Test("The row beneath the mouse is absent rather than -1 when there is no window")
	func rowBeneathMouseIsOptional() {
		let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

		#expect(table.rowBeneathMouse == nil)
	}

	@Test("Invalidating the selection background does not disturb the selection")
	func invalidatingSelectionKeepsTheSelection() {
		let table = SelectionCountingTableView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
		let source = SelectionCountingDataSource()
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
		table.dataSource = source
		table.reloadData()
		table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

		table.selectionChangeCount = 0
		table.invalidateSelectionBackground()

		#expect(table.selectedRowIndexes == IndexSet(integer: 1))
		#expect(table.selectionChangeCount == 0)
	}
}

private final class SelectionCountingTableView: NSTableView {
	var selectionChangeCount = 0

	override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
		selectionChangeCount += 1
		super.selectRowIndexes(indexes, byExtendingSelection: extend)
	}

	override func deselectAll(_ sender: Any?) {
		selectionChangeCount += 1
		super.deselectAll(sender)
	}
}

private final class SelectionCountingDataSource: NSObject, NSTableViewDataSource {
	func numberOfRows(in _: NSTableView) -> Int {
		3
	}

	func tableView(_: NSTableView, objectValueFor _: NSTableColumn?, row: Int) -> Any? {
		"row \(row)"
	}
}
