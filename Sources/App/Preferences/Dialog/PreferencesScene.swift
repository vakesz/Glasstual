/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsSceneRequest {
	private(set) var selection: PreferencesSceneSelection = .default
	private(set) var revision = 0

	func open(_ selection: PreferencesSceneSelection) {
		self.selection = selection
		revision &+= 1
	}
}

/// The `Settings` scene, as a named type like every other application scene.
struct PreferencesApplicationScene: Scene {
	let request: SettingsSceneRequest

	var body: some Scene {
		Settings {
			PreferencesSceneRoot(request: request)
		}
		/* The pages declare their own minimum, and the window used to let
		 itself be dragged narrower than any of them could lay out. */
		.windowResizability(.contentMinSize)
	}
}

struct PreferencesSceneRoot: View {
	let request: SettingsSceneRequest
	@State private var session = PreferencesSession()

	var body: some View {
		/* No frame here: `PreferencesRootView` declares the window's minimum,
		 ideal and maximum size, and a second frame would only fight it. */
		PreferencesRootView(model: session.model)
			.onAppear {
				session.activate(selection: request.selection)
			}
			.onChange(of: request.revision) {
				session.activate(selection: request.selection)
			}
			.onDisappear {
				session.deactivate()
			}
	}
}
