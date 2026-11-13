// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A transcript folder in the temporary directory, laid out the way the writer
/// lays it out. Removed by ``remove()``.
struct TranscriptLogFixture {
	let root: URL

	init() throws {
		root = FileManager.default.temporaryDirectory
			.appendingPathComponent("glasstual-log-viewer-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	}

	@discardableResult
	func write(_ text: String, server: String, folder: String, name: String? = nil, day: String) throws -> URL {
		var directory = root.appendingPathComponent(server, isDirectory: true)
			.appendingPathComponent(folder, isDirectory: true)
		if let name {
			directory.appendPathComponent(name, isDirectory: true)
		}
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let url = directory.appendingPathComponent("\(day).txt")
		try Data(text.utf8).write(to: url)

		return url
	}

	func remove() {
		try? FileManager.default.removeItem(at: root)
	}
}
