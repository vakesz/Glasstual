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
		/* A spotlight panel, not a document window: it floats over what it
		 searches, opens in the middle of the screen, carries no chrome of its
		 own so the glass effect is not drawn on an opaque square, and is never
		 restored — a search nobody asked to resume. */
		.windowStyle(.plain)
		.windowLevel(.floating)
		.defaultPosition(.center)
		.restorationBehavior(.disabled)
	}
}

private struct ChannelSpotlightSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	@Environment(\.controlActiveState) private var controlActiveState
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
			.onChange(of: controlActiveState) { _, state in
				// A spotlight panel goes away as soon as it stops being typed into.
				guard state != .key else { return }
				dismiss()
			}
		}
	}

	private func dismiss() {
		dismissWindow(id: ApplicationSceneID.channelSpotlight)
	}
}
