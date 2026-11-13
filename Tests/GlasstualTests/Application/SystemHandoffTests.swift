// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The end-to-end harness and this test host run the application on a
 person's own login. A link a scenario pressed once opened in that person's
 browser, again and again; nothing but an interactive launch may hand a URL,
 a file or a Help page to another application. */
@MainActor
@Suite("Handing off to another application")
struct SystemHandoffTests {
	@Test("Only an interactive launch hands anything to the system")
	func onlyInteractiveLaunchHandsOff() {
		#expect(ApplicationLaunchMode.interactive.handsOffToSystem)
		#expect(ApplicationLaunchMode.unitTestHost.handsOffToSystem == false)
		#expect(ApplicationLaunchMode.endToEnd(keepsRunState: false).handsOffToSystem == false)
		#expect(ApplicationLaunchMode.endToEnd(keepsRunState: true).handsOffToSystem == false)

		#expect(SystemHandoff.permits("a URL", in: .interactive))
		#expect(SystemHandoff.permits("a URL", in: .unitTestHost) == false)
		#expect(SystemHandoff.permits("a URL", in: .endToEnd(keepsRunState: false)) == false)
		#expect(SystemHandoff.permits("a URL", in: .endToEnd(keepsRunState: true)) == false)
	}

	@Test("This test host hands nothing off")
	func currentHostHandsNothingOff() {
		#expect(SystemHandoff.mode == .unitTestHost)
		#expect(SystemHandoff.permits("a URL") == false)
	}

	/// The guard holds only while every way out goes through it. A SwiftUI
	/// `Link` opens its destination through the environment's `openURL`, so a
	/// file that draws one has to set ``SystemHandoff/linkAction``.
	@Test("No other source file opens, reveals or performs anything outside the application")
	func everyHandoffGoesThroughTheOwner() throws {
		let sources = RepositoryPaths.root.appending(path: "Sources/App", directoryHint: .isDirectory)
		let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
		let calls = [
			"NSWorkspace.shared.open(", "activateFileViewerSelecting", "openHelpAnchor", "NSPerformService(",
			"openApplication(", "\\.openURL)",
		]
		var scanned = 0
		for case let file as URL in enumerator where file.pathExtension == "swift" {
			guard file.lastPathComponent != "SystemHandoff.swift" else { continue }
			let source = try String(contentsOf: file, encoding: .utf8)
			scanned += 1
			for call in calls {
				#expect(source.contains(call) == false, "\(file.lastPathComponent) calls \(call) itself")
			}
			if source.contains(" Link(") || source.contains("\tLink(") {
				#expect(
					source.contains("\\.openURL, SystemHandoff.linkAction"),
					"\(file.lastPathComponent) draws a Link without SystemHandoff.linkAction"
				)
			}
		}
		#expect(scanned > 100)
	}
}
