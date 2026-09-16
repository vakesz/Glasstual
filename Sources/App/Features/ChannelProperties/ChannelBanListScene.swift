/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ChannelBanListScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		Window(ChannelBanListStrings.accessList, id: ApplicationSceneID.channelAccessList) {
			ChannelBanListSceneRoot(scenes: scenes)
		}
		/* A list of the channel's current bans, not a document: what it shows is
		 whatever the server answers when it is opened, so there is nothing worth
		 restoring into an empty table on the next launch. */
		.restorationBehavior(.disabled)
	}
}

private struct ChannelBanListSceneRoot: View {
	let scenes: ApplicationScenes

	var body: some View {
		if let session = scenes.channelAccessListWindowState.session {
			ChannelBanListView(
				model: session.model,
				update: session.updateList,
				removeSelected: session.removeSelectedEntries
			)
			.navigationTitle(session.heading)
			.onDisappear {
				scenes.channelAccessListDidClose()
			}
		} else {
			ContentUnavailableView(
				ChannelBanListStrings.emptyTitle,
				systemImage: "checkmark.shield",
				description: Text(verbatim: ChannelBanListStrings.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 300)
		}
	}
}
