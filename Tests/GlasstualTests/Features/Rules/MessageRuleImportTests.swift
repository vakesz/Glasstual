// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct MessageRuleImportTests {
	@Test("Oversized rule files are refused before reading their contents")
	func oversizedFileIsRejected() async throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
		defer { try? FileManager.default.removeItem(at: url) }
		try Data().write(to: url)
		let handle = try FileHandle(forWritingTo: url)
		try handle.truncate(atOffset: UInt64(MessageRule.maximumDocumentBytes + 1))
		try handle.close()

		await #expect(throws: CocoaError(.fileReadTooLarge)) {
			try await MessageRule.read(from: url)
		}
	}

	@Test("A rule document must contain a dictionary")
	func arrayDocumentIsRejected() async throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
		defer { try? FileManager.default.removeItem(at: url) }
		try PropertyListEncoder().encode(["not a rule"]).write(to: url)
		await #expect(throws: CocoaError(.fileReadCorruptFile)) {
			try await MessageRule.read(from: url)
		}
	}

	@Test("Directories are refused as rule documents")
	func directoryIsRejected() async {
		await #expect(throws: CocoaError(.fileReadCorruptFile)) {
			try await MessageRule.read(from: FileManager.default.temporaryDirectory)
		}
	}

	@Test("A cancelled import does not attempt file access")
	func cancellationPrecedesFileAccess() async {
		let task = Task {
			try await MessageRule.read(from: URL(filePath: "/missing-rule.plist"))
		}
		task.cancel()
		await #expect(throws: CancellationError.self) {
			try await task.value
		}
	}
}
