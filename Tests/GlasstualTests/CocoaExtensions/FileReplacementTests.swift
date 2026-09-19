// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Testing

@MainActor
@Suite("Staged file replacement")
struct FileReplacementTests {
	@Test("Staging failure preserves the old item and same-location replacement preserves the source")
	func failedValidationAndSameLocationAreNonDestructive() throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try manager.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }
		let source = root.appendingPathComponent("source")
		let destination = root.appendingPathComponent("destination")
		try Data("new".utf8).write(to: source)
		try Data("old".utf8).write(to: destination)
		#expect(throws: (any Error).self) {
			try manager.stageAndReplaceItem(at: destination, withItemAt: source) { staged in
				#expect(staged != source)
				#expect(try Data(contentsOf: staged) == Data("new".utf8))
				#expect(try Data(contentsOf: destination) == Data("old".utf8))
				throw CocoaError(.fileReadCorruptFile)
			}
		}
		#expect(try Data(contentsOf: destination) == Data("old".utf8))
		#expect(try Data(contentsOf: source) == Data("new".utf8))
		#expect(try manager.contentsOfDirectory(atPath: root.path).sorted() == ["destination", "source"])
		#expect(throws: (any Error).self) {
			try manager.stageAndReplaceItem(at: destination, withItemAt: root.appendingPathComponent("missing"))
		}
		#expect(try Data(contentsOf: destination) == Data("old".utf8))
		try manager.stageAndReplaceItem(at: source, withItemAt: source)
		#expect(try Data(contentsOf: source) == Data("new".utf8))
		try manager.stageAndReplaceItem(at: destination, withItemAt: source)
		#expect(try Data(contentsOf: destination) == Data("new".utf8))
		#expect(try Data(contentsOf: source) == Data("new".utf8))
	}

	@Test("A bundle directory is swapped whole, without mixing old and new files")
	func directoryReplacementIsWhole() throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let source = root.appendingPathComponent("source.bundle", isDirectory: true)
		let destination = root.appendingPathComponent("installed.bundle", isDirectory: true)
		try manager.createDirectory(at: source, withIntermediateDirectories: true)
		try manager.createDirectory(at: destination, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }
		try Data("new".utf8).write(to: source.appendingPathComponent("new"))
		try Data("old".utf8).write(to: destination.appendingPathComponent("old"))
		try manager.stageAndReplaceItem(at: destination, withItemAt: source)
		#expect(try manager.contentsOfDirectory(atPath: destination.path) == ["new"])
		#expect(try manager.contentsOfDirectory(atPath: source.path) == ["new"])
		#expect(try manager.contentsOfDirectory(atPath: root.path).sorted() == ["installed.bundle", "source.bundle"])
	}

	/// A trash failure deliberately keeps the replaced item in its staging
	/// directory, and nothing else collects those, so the next install has to.
	@Test("An install clears the staging directories an earlier one orphaned")
	func installSweepsOrphanedStagingDirectories() throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try manager.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }
		let orphan = root.appendingPathComponent(".glasstual-install-\(UUID().uuidString)", isDirectory: true)
		try manager.createDirectory(at: orphan, withIntermediateDirectories: true)
		try Data("previous".utf8).write(to: orphan.appendingPathComponent("destination"))
		let unrelated = root.appendingPathComponent(".hidden")
		try Data("kept".utf8).write(to: unrelated)
		let source = root.appendingPathComponent("source")
		let destination = root.appendingPathComponent("destination")
		try Data("new".utf8).write(to: source)

		try manager.stageAndReplaceItem(at: destination, withItemAt: source)

		#expect(manager.fileExists(at: orphan) == false)
		#expect(try Data(contentsOf: destination) == Data("new".utf8))
		#expect(try Data(contentsOf: unrelated) == Data("kept".utf8))
	}

	@Test("A racing destination creation cannot be overwritten by an initial install")
	func initialInstallDoesNotClobberARacingCreate() throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try manager.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }
		let source = root.appendingPathComponent("source")
		let destination = root.appendingPathComponent("destination")
		try Data("new".utf8).write(to: source)
		#expect(throws: (any Error).self) {
			try manager.stageAndReplaceItem(at: destination, withItemAt: source) { _ in
				try Data("racing".utf8).write(to: destination)
			}
		}
		#expect(try Data(contentsOf: destination) == Data("racing".utf8))
		#expect(try Data(contentsOf: source) == Data("new".utf8))
	}

	@Test("Replacing an item refuses a non-file URL rather than reporting success")
	func replacingRejectsNonFileURLs() throws {
		let remote = try #require(URL(string: "https://example.test/theme"))
		let local = FileManager.default.temporaryDirectory.appendingPathComponent("glasstual-test")

		#expect(throws: (any Error).self) {
			try FileManager.default.stageAndReplaceItem(at: local, withItemAt: remote)
		}
		#expect(throws: (any Error).self) {
			try FileManager.default.stageAndReplaceItem(at: remote, withItemAt: local)
		}
	}

	@Test("An existing destination is replaced with the staged copy")
	func existingDestinationIsReplaced() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("glasstual-replace-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try Data("a".utf8).write(to: source)
		try Data("b".utf8).write(to: destination)

		try FileManager.default.stageAndReplaceItem(at: destination, withItemAt: source)
		#expect(try Data(contentsOf: destination) == Data("a".utf8))
	}
}
