/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ServerChannelListApplicationScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		WindowGroup(
			ServerChannelListStrings.windowGroupTitle,
			id: ApplicationSceneID.serverChannelList,
			for: String.self
		) { clientIdentifier in
			ServerChannelListSceneRoot(
				clientIdentifier: clientIdentifier.wrappedValue,
				scenes: scenes
			)
		}
		.defaultSize(width: 720, height: 420)
		/* A table of a whole network's channels: the window has a floor, not a
		 ceiling, and the reader is the one who decides how much of it to see. */
		.windowResizability(.contentMinSize)
	}
}

private struct ServerChannelListSceneRoot: View {
	let clientIdentifier: String?
	let scenes: ApplicationScenes

	var body: some View {
		if let clientIdentifier,
		   let session = scenes.serverChannelList(for: clientIdentifier)
		{
			ServerChannelListView(
				model: session.model,
				supportsMinimumUserCount: session.supportsMinimumUserCount,
				joinSelected: session.joinSelectedChannels,
				update: session.beginRefresh
			)
			.frame(minWidth: 600, idealWidth: 720, minHeight: 320, idealHeight: 420)
			/* The network names the window; how much of it arrived is a subtitle,
			 and it counts what the window kept rather than what the search field
			 has narrowed the table to. */
			.navigationTitle(session.networkName)
			.navigationSubtitle(
				ServerChannelListStrings.windowSubtitle(publicChannelCount: session.model.keptEntryCount)
			)
			.onDisappear {
				scenes.serverChannelListDidClose(for: clientIdentifier)
			}
		} else {
			ContentUnavailableView(
				ServerChannelListStrings.noChannelListTitle,
				systemImage: "number",
				description: Text(verbatim: ServerChannelListStrings.noChannelListDescription)
			)
			.frame(minWidth: 600, minHeight: 320)
		}
	}
}
