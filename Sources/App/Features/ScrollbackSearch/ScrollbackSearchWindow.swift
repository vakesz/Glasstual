// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The history search window, and what it is showing.

 One window: the search covers every conversation, so a second would repeat the
 first. The model outlives the window being closed for as long as the process
 does, which is what lets a reader reopen it on the results they left. */
@MainActor
final class ScrollbackSearchWindow {
	let model: ScrollbackSearchModel

	private let scenes: ApplicationScenes

	init(model: ScrollbackSearchModel = ScrollbackSearchModel(), scenes: ApplicationScenes = AppServices.scenes) {
		self.model = model
		self.scenes = scenes
	}

	func open() {
		model.refreshTargets()
		scenes.open(ApplicationSceneID.scrollbackSearch)
	}
}

struct ScrollbackSearchScene: Scene {
	let window: ScrollbackSearchWindow

	var body: some Scene {
		WindowGroup(
			String(localized: .ScrollbackSearch.windowTitle),
			id: ApplicationSceneID.scrollbackSearch,
			for: SingletonSceneValue.self
		) { _ in
			ScrollbackSearchView(model: window.model)
		} defaultValue: { .instance }
			.defaultSize(width: 760, height: 560)
			// Results are rebuilt from the store when the window opens, so there
			// is nothing worth restoring into an empty window on the next launch.
			.restorationBehavior(.disabled)
	}
}
