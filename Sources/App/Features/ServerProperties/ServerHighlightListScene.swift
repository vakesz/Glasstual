/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ServerHighlightListApplicationScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		/* Keyed by the connection, so each server's highlights get their own
		 window: a highlight is logged against one client, which is what routes
		 it to a list, and two connections would otherwise share a table. */
		WindowGroup(
			ServerHighlightListStrings.highlightList,
			id: ApplicationSceneID.serverHighlightList,
			for: String.self
		) { clientIdentifier in
			ServerHighlightListSceneRoot(
				clientIdentifier: clientIdentifier.wrappedValue,
				scenes: scenes
			)
		}
		.defaultSize(width: 760, height: 460)
		/* The list holds what was logged this session, and the log is the
		 client's rather than the window's: an empty table restored on the next
		 launch is not the list anybody left open. */
		.restorationBehavior(.disabled)
	}
}

private struct ServerHighlightListSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	let clientIdentifier: String?
	let scenes: ApplicationScenes

	var body: some View {
		if let clientIdentifier, let session = scenes.serverHighlightList(for: clientIdentifier) {
			ServerHighlightListView(
				model: session.model,
				networkName: session.networkName,
				activate: session.activateHighlight(withID:),
				clear: session.clearHighlights,
				close: {
					dismissWindow(id: ApplicationSceneID.serverHighlightList, value: clientIdentifier)
				}
			)
			.navigationTitle(ServerHighlightListStrings.windowTitle(networkName: session.networkName))
			.onDisappear {
				scenes.serverHighlightListDidClose(for: clientIdentifier)
			}
		} else {
			ContentUnavailableView(
				ServerHighlightListStrings.emptyTitle,
				systemImage: "exclamationmark.bubble",
				description: Text(verbatim: ServerHighlightListStrings.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 320)
		}
	}
}
