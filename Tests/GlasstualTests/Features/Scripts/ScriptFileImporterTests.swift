// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct ScriptFileImporterTests {
	@Test("An opened file is recognised by kind")
	func openedFilesAreClassified() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualImportTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let script = directory.appendingPathComponent("Example.scpt")
		try Data().write(to: script)

		let style = directory.appendingPathComponent("Example.css")
		try Data().write(to: style)

		#expect(ScriptFileImporter.isInstallableScript(script))
		#expect(ScriptFileImporter.isInstallableScript(style) == false)
	}

	@Test("Remote script URLs are not local installable files")
	func remoteScript() throws {
		let url = try #require(URL(string: "https://example.test/example.scpt"))
		#expect(ScriptFileImporter.isInstallableScript(url) == false)
	}
}
