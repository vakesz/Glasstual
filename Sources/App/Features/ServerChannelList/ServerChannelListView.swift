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

import AppKit
import CocoaExtensions
import SwiftUI

struct ServerChannelListView: View {
	@Bindable var model: ServerChannelListModel
	let networkName: String
	let supportsMinimumUserCount: Bool
	let joinSelected: () -> Void
	let activate: (ServerChannelListEntry.ID) -> Void
	let update: () -> Void
	let close: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			VStack(spacing: 10) {
				HStack {
					Text(verbatim: ServerChannelListStrings.heading(networkName: networkName))
						.font(.headline)
					Spacer()
					if model.isRefreshing {
						ProgressView()
							.controlSize(.small)
							.accessibilityLabel(ServerChannelListStrings.requestingChannelList)
					}
				}

				HStack {
					if supportsMinimumUserCount {
						Text(verbatim: ServerChannelListStrings.minimumUserCountLabel)
						TextField(
							"0",
							text: Binding(
								get: { model.minimumUserCount },
								set: model.setMinimumUserCount
							)
						)
						.frame(width: 64)
						.monospacedDigit()
						.help(ServerChannelListStrings.minimumUserCountHint)
					}

					Spacer()

					TextField(ServerChannelListStrings.searchPlaceholder, text: $model.searchString)
						.frame(width: 240)
						.accessibilityLabel(ServerChannelListStrings.searchAccessibilityLabel)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)

			Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					ServerChannelListStrings.channelName,
					sortUsing: ServerChannelListComparator(field: .channelName, order: .forward)
				) { entry in
					interactiveCell(entry.channelName, entryID: entry.id)
				}
				.width(min: 100, ideal: 150)

				TableColumn(
					ServerChannelListStrings.memberCount,
					sortUsing: ServerChannelListComparator(field: .memberCount, order: .forward)
				) { entry in
					interactiveCell(String(entry.memberCount), entryID: entry.id)
						.monospacedDigit()
				}
				.width(min: 70, ideal: 90, max: 120)

				TableColumn(
					ServerChannelListStrings.topic,
					sortUsing: ServerChannelListComparator(field: .topic, order: .forward)
				) { entry in
					Text(formattedTopic(entry.unformattedTopic))
						.lineLimit(1)
						.frame(maxWidth: .infinity, alignment: .leading)
						.contentShape(.rect)
						.help(entry.plainTopic)
						.onTapGesture(count: 2) { activate(entry.id) }
				}
				.width(min: 220, ideal: 420)
			}
			.overlay {
				if model.rows.isEmpty {
					if model.isRefreshing {
						ProgressView(ServerChannelListStrings.requestingChannelList)
					} else {
						ContentUnavailableView(
							ServerChannelListStrings.emptyTitle,
							systemImage: "number",
							description: Text(verbatim: ServerChannelListStrings.emptyDescription)
						)
					}
				}
			}
			.copyable(model.selectedCopyItems)
			.onChange(of: model.selection) { oldSelection, _ in
				model.limitSelection(from: oldSelection)
			}
			.accessibilityLabel(ServerChannelListStrings.channelListAccessibilityLabel)

			Divider()
			HStack {
				Button(ServerChannelListStrings.joinSelectedChannels, action: joinSelected)
					.buttonStyle(.borderedProminent)
					.disabled(model.selection.isEmpty)
				Spacer()
				Button(ServerChannelListStrings.updateList, action: update)
					.disabled(model.isRefreshing)
				Button(PromptStrings.Action.close, action: close)
					.keyboardShortcut(.cancelAction)
			}
			.padding(12)
		}
		.onExitCommand(perform: close)
	}

	private func interactiveCell(_ text: String, entryID: ServerChannelListEntry.ID) -> some View {
		Text(verbatim: text)
			.lineLimit(1)
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(.rect)
			.onTapGesture(count: 2) { activate(entryID) }
	}

	private func formattedTopic(_ topic: String) -> AttributedString {
		guard topic.isEmpty == false else { return AttributedString() }
		let formatted = (topic as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: 13),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString()
		return AttributedString(formatted)
	}
}
