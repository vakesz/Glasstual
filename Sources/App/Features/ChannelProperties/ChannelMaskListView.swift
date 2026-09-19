// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct ChannelMaskListScene: Scene {
	let window: ChannelMaskListWindow

	var body: some Scene {
		WindowGroup(
			String(localized: .ChannelProperties.accessList),
			id: ApplicationSceneID.channelMaskList,
			for: SingletonSceneValue.self
		) { _ in
			ChannelMaskListSceneRoot(window: window)
		} defaultValue: { .instance }
			/* A list of the channel's current bans, not a document: what it shows is
			 whatever the server answers when it is opened, so there is nothing worth
			 restoring into an empty table on the next launch. */
			.restorationBehavior(.disabled)
	}
}

private struct ChannelMaskListSceneRoot: View {
	let window: ChannelMaskListWindow

	var body: some View {
		if let session = window.current {
			ChannelMaskListView(
				model: session.model,
				update: session.updateList,
				removeSelected: session.removeSelectedEntries
			)
			.navigationTitle(session.heading)
			.onDisappear {
				window.didClose()
			}
		} else {
			ContentUnavailableView(
				String(localized: .ChannelProperties.emptyTitle),
				systemImage: "checkmark.shield",
				description: Text(.ChannelProperties.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 300)
		}
	}
}

struct ChannelMaskListView: View {
	@Bindable var model: ChannelMaskListModel
	let update: () -> Void
	let removeSelected: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Spacer()
				if model.isRefreshing {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel(.ChannelProperties.loadingList)
				}
				Text(verbatim: model.entryCountDescription)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			.padding(.horizontal, SheetMetrics.margin)
			.padding(.vertical, UISpacing.wide)

			Table(model.entries, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					.ChannelProperties.hostmask,
					sortUsing: ChannelMaskListComparator(field: .mask, order: .forward)
				) { entry in
					Text(verbatim: entry.entryMask)
						.lineLimit(1)
						.help(entry.entryMaskDescription ?? entry.entryMask)
				}
				.width(min: 220, ideal: 360)

				TableColumn(
					.ChannelProperties.addedBy,
					sortUsing: ChannelMaskListComparator(field: .author, order: .forward)
				) { entry in
					Text(verbatim: entry.entryAuthor).lineLimit(1)
				}
				.width(min: 100, ideal: 140)

				TableColumn(
					.ChannelProperties.created,
					sortUsing: ChannelMaskListComparator(field: .creationDate, order: .forward)
				) { entry in
					Text(verbatim: entry.entryCreationDateString).lineLimit(1)
				}
				.width(min: 120, ideal: 160)
			}
			.overlay {
				if model.entries.isEmpty, model.isRefreshing == false {
					ContentUnavailableView(
						String(localized: .ChannelProperties.emptyTitle),
						systemImage: "checkmark.shield",
						description: Text(.ChannelProperties.emptyDescription)
					)
				}
			}
			.copyable(model.selectedMasks)
			.onDeleteCommand(perform: removeSelected)
			.contextMenu(forSelectionType: ChannelMaskListEntry.ID.self) { selection in
				Button(.ChannelProperties.removeSelected, role: .destructive) {
					model.selection = selection
					removeSelected()
				}
				.disabled(selection.isEmpty)
			}
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(.ChannelProperties.accessList)

			if let notice = model.truncationNotice {
				Text(notice)
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, SheetMetrics.margin)
					.padding(.top, UISpacing.regular)
			}

			Divider()
			HStack {
				Button(.ChannelProperties.removeSelected, role: .destructive, action: removeSelected)
					.disabled(model.selection.isEmpty)
				Spacer()
				Button(.ChannelProperties.updateList, action: update)
					.keyboardShortcut("r", modifiers: .command)
					.disabled(model.isRefreshing)
			}
			.padding(UISpacing.wide)
		}
		.frame(
			minWidth: 580,
			idealWidth: 680,
			minHeight: 320,
			idealHeight: 400
		)
	}
}
