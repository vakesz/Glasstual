// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The transcript log window, and what it is showing.

 One window: the logs are the folder's, not a connection's, so a second window
 would show the same tree. The model outlives the window being closed only for
 as long as the process does, and is read again each time the window opens, so
 it never shows a folder as it was last week. */
@MainActor
final class TranscriptLogViewerWindow {
	let model = TranscriptLogViewerModel()

	private let scenes: ApplicationScenes

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	func open() {
		scenes.open(ApplicationSceneID.transcriptLogViewer)
	}
}

struct TranscriptLogViewerScene: Scene {
	let window: TranscriptLogViewerWindow

	var body: some Scene {
		WindowGroup(
			String(localized: .TranscriptLogViewer.windowTitle),
			id: ApplicationSceneID.transcriptLogViewer,
			for: SingletonSceneValue.self
		) { _ in
			TranscriptLogViewerView(
				model: window.model,
				openSettings: { AppServices.scenes.openSettings() }
			)
		} defaultValue: { .instance }
			.defaultSize(width: 1040, height: 640)
			/* What it shows is whatever is on disk when it opens, so there is
			 nothing worth restoring into an empty window on the next launch. */
			.restorationBehavior(.disabled)
	}
}
