/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

struct ServerHighlightListScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		/* Keyed by the connection, so each server's highlights get their own
		 window: a highlight is logged against one client, which is what routes
		 it to a list, and two connections would otherwise share a table. */
		WindowGroup(
			String(localized: .ServerProperties.highlightList),
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
	let clientIdentifier: String?
	let scenes: ApplicationScenes

	var body: some View {
		if let clientIdentifier, let list = scenes.serverHighlightList(for: clientIdentifier) {
			ServerHighlightListView(
				model: list.model,
				activate: list.activateHighlight(withID:),
				clear: list.clearHighlights
			)
			.navigationTitle(String(localized: .ServerProperties.windowTitle(list.networkName)))
			.onDisappear {
				scenes.serverHighlightListDidClose(for: clientIdentifier)
			}
		} else {
			ContentUnavailableView(
				String(localized: .ServerProperties.emptyTitle),
				systemImage: "exclamationmark.bubble",
				description: Text(.ServerProperties.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 320)
		}
	}
}

struct ServerHighlightListView: View {
	@Bindable var model: ServerHighlightListModel
	let activate: (String) -> Void
	let clear: () -> Void

	@State private var clearConfirmationIsPresented = false

	var body: some View {
		VStack(spacing: 0) {
			Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					.ServerProperties.channel,
					sortUsing: ServerHighlightListComparator(field: .channel, order: .forward)
				) { row in
					Text(verbatim: row.channelName).lineLimit(1)
				}
				.width(min: 90, ideal: 130)

				TableColumn(String(localized: .ServerProperties.message)) { row in
					Text(row.message).lineLimit(1)
				}
				.width(min: 220, ideal: 420)

				TableColumn(
					.ServerProperties.time,
					sortUsing: ServerHighlightListComparator(field: .time, order: .forward)
				) { row in
					/* The relative time went stale the moment it was drawn: it
					 said "1 minute ago" for as long as the window stayed open. */
					TimelineView(.everyMinute) { context in
						Text(verbatim: row.timeLabel(relativeTo: context.date)).lineLimit(1)
					}
				}
				.width(min: 100, ideal: 130)
			}
			.overlay {
				if model.rows.isEmpty {
					ContentUnavailableView(
						String(localized: .ServerProperties.emptyTitle),
						systemImage: "exclamationmark.bubble",
						description: Text(.ServerProperties.emptyDescription)
					)
				}
			}
			.copyable(model.selectedCopyItems)
			/* Opening the row is the table's primary action, so it is a
			 double-click, Return and the context menu at once -- which a tap
			 gesture on each cell was none of. */
			.contextMenu(forSelectionType: ServerHighlightListRow.ID.self) { selection in
				Button(.ServerProperties.goToMessage) { open(selection) }
					.disabled(selection.count != 1)
			} primaryAction: { selection in
				open(selection)
			}
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(.ServerProperties.highlightList)

			Divider()
			HStack {
				Text(.ServerProperties.actionNote)
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button(.ServerProperties.clearList, role: .destructive) {
					clearConfirmationIsPresented = true
				}
				.disabled(model.rows.isEmpty)
			}
			.padding(12)
		}
		.confirmationDialog(
			.ServerProperties.clearListConfirmationTitle,
			isPresented: $clearConfirmationIsPresented
		) {
			Button(.ServerProperties.clearList, role: .destructive, action: clear)
			Button(PromptStrings.Action.cancel, role: .cancel) {}
		} message: {
			Text(.ServerProperties.clearListConfirmationMessage)
		}
		.frame(
			minWidth: 620,
			idealWidth: 760,
			maxWidth: .infinity,
			minHeight: 380,
			idealHeight: 460,
			maxHeight: .infinity
		)
	}

	private func open(_ selection: Set<ServerHighlightListRow.ID>) {
		guard let id = selection.first, selection.count == 1 else { return }
		activate(id)
	}
}
