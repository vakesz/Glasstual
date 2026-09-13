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

struct ServerHighlightListView: View {
	@Bindable var model: ServerHighlightListModel
	let activate: (String) -> Void
	let clear: () -> Void

	@State private var clearConfirmationIsPresented = false

	var body: some View {
		VStack(spacing: 0) {
			Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					ServerHighlightListStrings.channel,
					sortUsing: ServerHighlightListComparator(field: .channel, order: .forward)
				) { row in
					Text(verbatim: row.channelName).lineLimit(1)
				}
				.width(min: 90, ideal: 130)

				TableColumn(ServerHighlightListStrings.message) { row in
					Text(row.message).lineLimit(1)
				}
				.width(min: 220, ideal: 420)

				TableColumn(
					ServerHighlightListStrings.time,
					sortUsing: ServerHighlightListComparator(field: .time, order: .forward)
				) { row in
					Text(verbatim: row.timeLabel).lineLimit(1)
				}
				.width(min: 100, ideal: 130)
			}
			.overlay {
				if model.rows.isEmpty {
					ContentUnavailableView(
						ServerHighlightListStrings.emptyTitle,
						systemImage: "exclamationmark.bubble",
						description: Text(verbatim: ServerHighlightListStrings.emptyDescription)
					)
				}
			}
			.copyable(model.selectedCopyItems)
			/* Opening the row is the table's primary action, so it is a
			 double-click, Return and the context menu at once -- which a tap
			 gesture on each cell was none of. */
			.contextMenu(forSelectionType: ServerHighlightListRow.ID.self) { selection in
				Button(ServerHighlightListStrings.goToMessage) { open(selection) }
					.disabled(selection.count != 1)
			} primaryAction: { selection in
				open(selection)
			}
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(ServerHighlightListStrings.highlightList)

			Divider()
			HStack {
				Text(verbatim: ServerHighlightListStrings.actionNote)
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button(ServerHighlightListStrings.clearList, role: .destructive) {
					clearConfirmationIsPresented = true
				}
				.disabled(model.rows.isEmpty)
			}
			.padding(12)
		}
		.confirmationDialog(
			ServerHighlightListStrings.clearListConfirmationTitle,
			isPresented: $clearConfirmationIsPresented
		) {
			Button(ServerHighlightListStrings.clearList, role: .destructive, action: clear)
			Button(PromptStrings.Action.cancel, role: .cancel) {}
		} message: {
			Text(verbatim: ServerHighlightListStrings.clearListConfirmationMessage)
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
