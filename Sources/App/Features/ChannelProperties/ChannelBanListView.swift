/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct ChannelBanListView: View {
	private enum Layout {
		static let minimumWidth: CGFloat = 580
		static let idealWidth: CGFloat = 680
		static let minimumHeight: CGFloat = 320
		static let idealHeight: CGFloat = 400
	}

	@Bindable var model: ChannelBanListModel
	let heading: String
	let update: () -> Void
	let removeSelected: () -> Void
	let close: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Text(verbatim: heading).font(.headline)
				Spacer()
				if model.isRefreshing {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel(ChannelAccessListStrings.loadingList)
				}
				Text(verbatim: model.entryCountDescription)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			.padding(.horizontal, 20)
			.padding(.vertical, 12)

			Table(model.entries, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					ChannelAccessListStrings.hostmask,
					sortUsing: ChannelBanListComparator(field: .mask, order: .forward)
				) { entry in
					Text(verbatim: entry.entryMask)
						.lineLimit(1)
						.help(entry.entryMaskDescription ?? entry.entryMask)
				}
				.width(min: 220, ideal: 360)

				TableColumn(
					ChannelAccessListStrings.addedBy,
					sortUsing: ChannelBanListComparator(field: .author, order: .forward)
				) { entry in
					Text(verbatim: entry.entryAuthor).lineLimit(1)
				}
				.width(min: 100, ideal: 140)

				TableColumn(
					ChannelAccessListStrings.created,
					sortUsing: ChannelBanListComparator(field: .creationDate, order: .forward)
				) { entry in
					Text(verbatim: entry.entryCreationDateString).lineLimit(1)
				}
				.width(min: 120, ideal: 160)
			}
			.overlay {
				if model.entries.isEmpty, model.isRefreshing == false {
					ContentUnavailableView(
						ChannelAccessListStrings.emptyTitle,
						systemImage: "checkmark.shield",
						description: Text(verbatim: ChannelAccessListStrings.emptyDescription)
					)
				}
			}
			.copyable(model.selectedMasks)
			.onDeleteCommand(perform: removeSelected)
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(ChannelAccessListStrings.accessList)

			Divider()
			HStack {
				Button(ChannelAccessListStrings.removeSelected, role: .destructive, action: removeSelected)
					.disabled(model.selection.isEmpty)
				Spacer()
				Button(ChannelAccessListStrings.updateList, action: update)
					.disabled(model.isRefreshing)
				Button(PromptStrings.Action.close, action: close)
					.keyboardShortcut(.cancelAction)
			}
			.padding(12)
		}
		.onExitCommand(perform: close)
		.frame(
			minWidth: Layout.minimumWidth,
			idealWidth: Layout.idealWidth,
			minHeight: Layout.minimumHeight,
			idealHeight: Layout.idealHeight
		)
	}
}
