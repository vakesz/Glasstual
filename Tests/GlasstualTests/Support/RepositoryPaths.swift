// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/// The checkout the suite is running out of, for the tests that read the source
/// tree itself: the string catalogs, the settings-key declarations, the privacy
/// manifests and the checked-in corpora.
///
/// Every one of those used to spell the way out of `#filePath` as its own chain
/// of `deletingLastPathComponent()` calls, counted by hand against the folder
/// the test happened to sit in. Moving a test one folder deeper silently
/// pointed the chain at the wrong directory — loudly where the walk then found
/// nothing, and vacuously where "found nothing" is what the test asserts. The
/// root is found here instead of counted, so a test's own location is no longer
/// part of the contract.
nonisolated enum RepositoryPaths {
	/// The nearest ancestor of this file holding both `project.yml` and
	/// `AGENTS.md`, which together identify the checkout root.
	static let root: URL = {
		let start = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		var directory = start

		for _ in 0 ..< 8 {
			let manager = FileManager.default

			let hasSpec = manager.fileExists(atPath: directory.appending(path: "project.yml").path)
			let hasGuide = manager.fileExists(atPath: directory.appending(path: "AGENTS.md").path)

			if hasSpec, hasGuide {
				return directory
			}

			directory = directory.deletingLastPathComponent()
		}

		Issue.record("no repository root above \(start.path): project.yml and AGENTS.md were not found")

		return start
	}()

	/// `Sources`, holding both targets' Swift and their string catalogs.
	static var sources: URL {
		root.appending(path: "Sources")
	}

	/// `Sources/App`, the application target alone.
	static var appSources: URL {
		sources.appending(path: "App")
	}

	/// `Tests/Corpora`, the checked-in fixtures the suites read back.
	static var corpora: URL {
		root.appending(path: "Tests/Corpora")
	}
}
