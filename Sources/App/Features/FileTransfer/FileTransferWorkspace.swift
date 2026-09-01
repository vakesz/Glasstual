/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/// The feature's narrow bridge to Finder and the user's default applications.
@MainActor
enum FileTransferWorkspace {
	static func open(_ urls: [URL]) {
		urls.forEach { NSWorkspace.shared.open($0) }
	}

	static func reveal(_ urls: [URL]) {
		guard urls.isEmpty == false else { return }
		NSWorkspace.shared.activateFileViewerSelecting(urls)
	}
}
