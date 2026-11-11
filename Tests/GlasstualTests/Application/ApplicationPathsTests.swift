// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Application paths")
struct ApplicationPathsTests {
	@Test("Bundle and bundled resource locations point into the main bundle")
	func applicationPathsExposeBundleAndBundledResourceLocations() {
		let bundle = Bundle.main

		#expect(ApplicationPaths.applicationBundleURL == bundle.bundleURL)
		#expect(ApplicationPaths.applicationResourcesURL == bundle.resourceURL)
		#expect(ApplicationPaths.bundledScriptsURL.path.hasSuffix("Bundled Scripts"))
		#expect(ApplicationPaths.systemDiagnosticReportsURL.path == "/Library/Logs/DiagnosticReports")
	}

	@Test("An explicitly named directory is created on demand")
	func applicationPathsCreateExplicitDirectory() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: true)

		#expect(FileManager.default.fileExists(atPath: directory.path) == false)

		ApplicationPaths.createDirectory(at: directory)

		#expect(FileManager.default.fileExists(atPath: directory.path))
		try FileManager.default.removeItem(at: directory)
		#expect(FileManager.default.fileExists(atPath: directory.path) == false)
	}

	/// The path used to be recorded as ensured before the creation was even
	/// attempted, so a directory that failed once was never tried again.
	@Test("A directory that could not be created is created on the next call")
	func applicationPathsRetryADirectoryTheyCouldNotCreate() throws {
		let fileManager = FileManager.default
		let blocker = fileManager.temporaryDirectory
			.appendingPathComponent("GlasstualPathTests-\(UUID().uuidString)", isDirectory: false)
		let directory = blocker.appendingPathComponent("directory", isDirectory: true)
		defer { try? fileManager.removeItem(at: blocker) }

		/* A directory cannot be made inside a regular file. */
		try Data().write(to: blocker)

		ApplicationPaths.createDirectory(at: directory)

		#expect(fileManager.fileExists(atPath: directory.path) == false)

		try fileManager.removeItem(at: blocker)

		ApplicationPaths.createDirectory(at: directory)

		#expect(fileManager.fileExists(atPath: directory.path))
	}
}
