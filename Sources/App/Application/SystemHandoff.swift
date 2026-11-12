// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import os
import SwiftUI

private let systemHandoffLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "SystemHandoff"
)

/** The one owner of handing something to another application.

 Opening a URL starts the browser or whatever registered its scheme, revealing
 a file brings the Finder forward, and Help opens the Help viewer. Each of
 those happens on the login of whoever launched this process. The end-to-end
 harness and the unit-test host run the application on a person's own login
 while they work, so only an interactive launch hands anything off: there, a
 link pressed by a scenario would open in that person's browser.

 Every call that leaves the application goes through here, and
 `SystemHandoffTests` checks that no other file makes one. */
enum SystemHandoff {
	static let mode = ApplicationLaunchMode.current

	/// Whether a launch in `mode` may hand `what` off. A refusal is logged,
	/// so a run's log says what it would have opened.
	static func permits(_ what: String, in mode: ApplicationLaunchMode = mode) -> Bool {
		guard mode.handsOffToSystem else {
			systemHandoffLogger.info("Kept \(what, privacy: .public) inside the application: not an interactive launch")
			return false
		}
		return true
	}

	/// Opens `url` in the application registered for it, in front or behind.
	static func open(_ url: URL, activates: Bool = true) {
		guard permits("a \(url.scheme ?? "") URL") else { return }
		guard activates == false else {
			NSWorkspace.shared.open(url)
			return
		}
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = false
		NSWorkspace.shared.open(url, configuration: configuration)
	}

	/// Opens the file at `url` and waits until the system has taken it.
	static func openFile(_ url: URL) async throws {
		guard permits("a file") else { return }
		_ = try await NSWorkspace.shared.open(url, configuration: .init())
	}

	/// Selects `urls` in a Finder window.
	static func reveal(_ urls: [URL]) {
		guard permits("files to reveal") else { return }
		NSWorkspace.shared.activateFileViewerSelecting(urls)
	}

	/// Opens the Help viewer at `anchor` of `book`.
	static func openHelp(anchor: String, book: String?) {
		guard permits("a Help page") else { return }
		NSHelpManager.shared.openHelpAnchor(
			NSHelpManager.AnchorName(anchor),
			inBook: book.map { NSHelpManager.BookName($0) }
		)
	}

	/// Performs the system service `name` on what `pasteboard` holds.
	static func performService(_ name: String, with pasteboard: NSPasteboard) {
		guard permits("a system service") else { return }
		NSPerformService(name, pasteboard)
	}

	/// What a SwiftUI `Link` does when it is pressed. Set as the `openURL`
	/// of every view that draws one.
	static let linkAction = OpenURLAction { url in
		permits("a \(url.scheme ?? "") URL") ? .systemAction : .discarded
	}
}
