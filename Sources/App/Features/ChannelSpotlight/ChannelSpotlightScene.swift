/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ChannelSpotlightApplicationScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		Window(ChannelSpotlightStrings.accessibilityTitle, id: ApplicationSceneID.channelSpotlight) {
			ChannelSpotlightSceneRoot(scenes: scenes)
		}
		.windowResizability(.contentSize)
		.windowStyle(.hiddenTitleBar)
	}
}

private struct ChannelSpotlightSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	let scenes: ApplicationScenes

	var body: some View {
		if let session = scenes.currentChannelSpotlightSession() {
			ChannelSpotlightView(
				model: session.model,
				select: { result in
					session.select(result)
					dismiss()
				},
				close: dismiss
			)
			.onDisappear {
				scenes.channelSpotlightDidClose()
			}
		}
	}

	private func dismiss() {
		dismissWindow(id: ApplicationSceneID.channelSpotlight)
	}
}
