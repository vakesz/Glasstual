// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript image export")
struct TranscriptImageExportTests {
	@Test("An image with no representation reports an encoding failure")
	func missingImageRepresentationFails() {
		#expect(throws: TranscriptImageExport.Failure.self) {
			try TranscriptImageExport.pngData(from: NSImage())
		}
		#expect(TranscriptImageExport.Failure.encoding.localizedDescription == String(localized: .Transcript.imageEncodingFailed))
	}

	@Test("A rendered image exports as a readable PNG")
	func imageExportsToPNG() throws {
		let image = NSImage(size: NSSize(width: 12, height: 8), flipped: false) { rect in
			NSColor.systemBlue.setFill()
			rect.fill()
			return true
		}
		let data = try TranscriptImageExport.pngData(from: image)
		#expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
		let bitmap = try #require(NSBitmapImageRep(data: data))
		#expect(bitmap.pixelsWide > 0)
		#expect(bitmap.pixelsHigh > 0)
	}

	@Test("Saving propagates filesystem failure and successfully replaces an existing export")
	func fileWriteReportsFailure() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: directory) }
		let bytes = Data([1, 2, 3, 4])
		let missingParent = directory.appendingPathComponent("missing/export.png")
		await #expect(throws: (any Error).self) {
			try await TranscriptImageExport.write(bytes, to: missingParent)
		}
		#expect(FileManager.default.fileExists(atPath: missingParent.path) == false)

		let destination = directory.appendingPathComponent("export.png")
		try Data([9]).write(to: destination)
		try await TranscriptImageExport.write(bytes, to: destination)
		let saved = try Data(contentsOf: destination)
		#expect(saved == bytes)
	}
}
