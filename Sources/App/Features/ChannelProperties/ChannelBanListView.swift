/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ChannelBanListScene: Scene {
	let scenes: ApplicationScenes

	var body: some Scene {
		Window(String(localized: .ChannelBanList.accessList), id: ApplicationSceneID.channelBanList) {
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
		if let session = scenes.channelBanListWindowState.session {
			ChannelBanListView(
				model: session.model,
				update: session.updateList,
				removeSelected: session.removeSelectedEntries
			)
			.navigationTitle(session.heading)
			.onDisappear {
				scenes.channelBanListDidClose()
			}
		} else {
			ContentUnavailableView(
				String(localized: .ChannelBanList.emptyTitle),
				systemImage: "checkmark.shield",
				description: Text(.ChannelBanList.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 300)
		}
	}
}

struct ChannelBanListView: View {
	private enum Layout {
		static let minimumWidth: CGFloat = 580
		static let idealWidth: CGFloat = 680
		static let minimumHeight: CGFloat = 320
		static let idealHeight: CGFloat = 400
	}

	@Bindable var model: ChannelBanListModel
	let update: () -> Void
	let removeSelected: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Spacer()
				if model.isRefreshing {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel(.ChannelBanList.loadingList)
				}
				Text(verbatim: model.entryCountDescription)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			.padding(.horizontal, 20)
			.padding(.vertical, 12)

			Table(model.entries, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					.ChannelBanList.hostmask,
					sortUsing: ChannelBanListComparator(field: .mask, order: .forward)
				) { entry in
					Text(verbatim: entry.entryMask)
						.lineLimit(1)
						.help(entry.entryMaskDescription ?? entry.entryMask)
				}
				.width(min: 220, ideal: 360)

				TableColumn(
					.ChannelBanList.addedBy,
					sortUsing: ChannelBanListComparator(field: .author, order: .forward)
				) { entry in
					Text(verbatim: entry.entryAuthor).lineLimit(1)
				}
				.width(min: 100, ideal: 140)

				TableColumn(
					.ChannelBanList.created,
					sortUsing: ChannelBanListComparator(field: .creationDate, order: .forward)
				) { entry in
					Text(verbatim: entry.entryCreationDateString).lineLimit(1)
				}
				.width(min: 120, ideal: 160)
			}
			.overlay {
				if model.entries.isEmpty, model.isRefreshing == false {
					ContentUnavailableView(
						String(localized: .ChannelBanList.emptyTitle),
						systemImage: "checkmark.shield",
						description: Text(.ChannelBanList.emptyDescription)
					)
				}
			}
			.copyable(model.selectedMasks)
			.onDeleteCommand(perform: removeSelected)
			.contextMenu(forSelectionType: ChannelBanListEntry.ID.self) { selection in
				Button(.ChannelBanList.removeSelected, role: .destructive) {
					model.selection = selection
					removeSelected()
				}
				.disabled(selection.isEmpty)
			}
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(.ChannelBanList.accessList)

			if let notice = model.truncationNotice {
				Text(notice)
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 20)
					.padding(.top, 8)
			}

			Divider()
			HStack {
				Button(.ChannelBanList.removeSelected, role: .destructive, action: removeSelected)
					.disabled(model.selection.isEmpty)
				Spacer()
				Button(.ChannelBanList.updateList, action: update)
					.keyboardShortcut("r", modifiers: .command)
					.disabled(model.isRefreshing)
			}
			.padding(12)
		}
		.frame(
			minWidth: Layout.minimumWidth,
			idealWidth: Layout.idealWidth,
			minHeight: Layout.minimumHeight,
			idealHeight: Layout.idealHeight
		)
	}
}
