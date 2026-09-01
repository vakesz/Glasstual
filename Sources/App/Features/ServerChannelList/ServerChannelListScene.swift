/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ServerChannelListApplicationScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		WindowGroup(
			ServerChannelListStrings.channelListAccessibilityLabel,
			id: ApplicationSceneID.serverChannelList,
			for: String.self
		) { clientIdentifier in
			ServerChannelListSceneRoot(
				clientIdentifier: clientIdentifier.wrappedValue,
				scenes: scenes
			)
		}
		.defaultSize(width: 720, height: 420)
		.windowResizability(.contentSize)
	}
}

private struct ServerChannelListSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	let clientIdentifier: String?
	let scenes: ApplicationScenes

	var body: some View {
		if let clientIdentifier,
		   let session = scenes.serverChannelList(for: clientIdentifier)
		{
			ServerChannelListView(
				model: session.model,
				networkName: session.networkName,
				supportsMinimumUserCount: session.supportsMinimumUserCount,
				joinSelected: session.joinSelectedChannels,
				activate: session.activate,
				update: session.beginRefresh,
				close: {
					dismissWindow(id: ApplicationSceneID.serverChannelList, value: clientIdentifier)
				}
			)
			.frame(
				minWidth: 600,
				idealWidth: 720,
				maxWidth: 1024,
				minHeight: 320,
				idealHeight: 420,
				maxHeight: 720
			)
			.navigationTitle(ServerChannelListStrings.windowTitle(publicChannelCount: session.model.rows.count))
			.onDisappear {
				scenes.serverChannelListDidClose(for: clientIdentifier)
			}
		} else {
			ContentUnavailableView(
				ServerChannelListStrings.channelListAccessibilityLabel,
				systemImage: "number"
			)
			.frame(minWidth: 600, minHeight: 320)
		}
	}
}
