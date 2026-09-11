/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ChannelAccessListApplicationScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		Window(ChannelAccessListStrings.accessList, id: ApplicationSceneID.channelAccessList) {
			ChannelAccessListSceneRoot(scenes: scenes)
		}
		/* A list of the channel's current bans, not a document: what it shows is
		 whatever the server answers when it is opened, so there is nothing worth
		 restoring into an empty table on the next launch. */
		.restorationBehavior(.disabled)
	}
}

private struct ChannelAccessListSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	let scenes: ApplicationScenes

	var body: some View {
		if let session = scenes.channelAccessListWindowState.session {
			ChannelBanListView(
				model: session.model,
				heading: session.heading,
				update: session.updateList,
				removeSelected: session.removeSelectedEntries,
				close: dismiss
			)
			.navigationTitle(session.heading)
			.onDisappear {
				scenes.channelAccessListDidClose()
			}
		} else {
			ContentUnavailableView(
				ChannelAccessListStrings.emptyTitle,
				systemImage: "checkmark.shield",
				description: Text(verbatim: ChannelAccessListStrings.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 300)
		}
	}

	private func dismiss() {
		dismissWindow(id: ApplicationSceneID.channelAccessList)
	}
}
