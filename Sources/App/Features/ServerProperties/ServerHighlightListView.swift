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
	let networkName: String
	let activate: (String) -> Void
	let clear: () -> Void
	let close: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			Text(verbatim: ServerHighlightListStrings.heading(networkName: networkName))
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.vertical, 12)

			Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					ServerHighlightListStrings.channel,
					sortUsing: ServerHighlightListComparator(field: .channel, order: .forward)
				) { row in
					cell(row.channelName, rowID: row.id)
				}
				.width(min: 90, ideal: 130)

				TableColumn(ServerHighlightListStrings.message) { row in
					Text(row.message)
						.lineLimit(1)
						.frame(maxWidth: .infinity, alignment: .leading)
						.contentShape(.rect)
						.onTapGesture(count: 2) { activate(row.id) }
				}
				.width(min: 220, ideal: 420)

				TableColumn(
					ServerHighlightListStrings.time,
					sortUsing: ServerHighlightListComparator(field: .time, order: .forward)
				) { row in
					cell(row.timeLabel, rowID: row.id)
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
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(ServerHighlightListStrings.highlightList)

			Divider()
			HStack {
				Text(verbatim: ServerHighlightListStrings.actionNote)
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button(ServerHighlightListStrings.clearList, role: .destructive, action: clear)
					.disabled(model.rows.isEmpty)
				Button(PromptStrings.Action.close, action: close)
					.keyboardShortcut(.cancelAction)
			}
			.padding(12)
		}
		.onExitCommand(perform: close)
	}

	private func cell(_ text: String, rowID: String) -> some View {
		Text(verbatim: text)
			.lineLimit(1)
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(.rect)
			.onTapGesture(count: 2) { activate(rowID) }
	}
}
