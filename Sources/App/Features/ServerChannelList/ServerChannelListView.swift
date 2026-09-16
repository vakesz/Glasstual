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
	let supportsMinimumUserCount: Bool
	let joinSelected: () -> Void
	let update: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			channelTable
			Divider()
			footer
		}
		.searchable(
			text: $model.searchString,
			placement: .toolbar,
			prompt: Text(verbatim: ServerChannelListStrings.searchPlaceholder)
		)
	}

	private var channelTable: some View {
		Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
			TableColumn(
				ServerChannelListStrings.channelName,
				sortUsing: ServerChannelListComparator(field: .channelName, order: .forward)
			) { entry in
				Text(verbatim: entry.channelName)
					.lineLimit(1)
			}
			.width(min: 100, ideal: 150)

			TableColumn(
				ServerChannelListStrings.memberCount,
				sortUsing: ServerChannelListComparator(field: .memberCount, order: .forward)
			) { entry in
				Text(entry.memberCount, format: .number)
					.monospacedDigit()
			}
			.width(min: 70, ideal: 90, max: 120)

			TableColumn(
				ServerChannelListStrings.topic,
				sortUsing: ServerChannelListComparator(field: .topic, order: .forward)
			) { entry in
				Text(formattedTopic(entry.displayedTopic))
					.lineLimit(1)
					.help(entry.plainTopic)
			}
			.width(min: 220, ideal: 420)
		}
		/* The table's own selection menu, which is what carries the clicked rows
		 into the command and makes the double click the same command again. */
		.contextMenu(forSelectionType: ServerChannelListEntry.ID.self) { identifiers in
			Button(ServerChannelListStrings.joinSelectedChannels) {
				join(identifiers)
			}
			.disabled(identifiers.isEmpty)
		} primaryAction: { identifiers in
			join(identifiers)
		}
		.overlay {
			if model.rows.isEmpty {
				if model.isRefreshing || model.isFiltering {
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
		.accessibilityLabel(ServerChannelListStrings.channelListAccessibilityLabel)
	}

	private var footer: some View {
		VStack(alignment: .leading, spacing: UISpacing.regular) {
			if let notice = model.truncationNotice {
				Text(verbatim: notice)
					.font(.callout)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}

			HStack(alignment: .firstTextBaseline, spacing: UISpacing.regular) {
				if supportsMinimumUserCount {
					LabeledContent(ServerChannelListStrings.minimumUserCountLabel) {
						TextField(
							"0",
							text: Binding(
								get: { model.minimumUserCount },
								set: model.setMinimumUserCount
							)
						)
						.frame(width: 64)
						.monospacedDigit()
					}
					.fixedSize()
				}

				Spacer()

				if model.isRefreshing || model.isFiltering {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel(ServerChannelListStrings.requestingChannelList)
				}

				Button(ServerChannelListStrings.refresh, action: update)
					.keyboardShortcut("r", modifiers: .command)
					.disabled(model.isRefreshing)

				Button(ServerChannelListStrings.joinSelectedChannels, action: joinSelected)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(model.selection.isEmpty)
			}

			if supportsMinimumUserCount {
				Text(verbatim: ServerChannelListStrings.minimumUserCountFooter)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.padding(UISpacing.wide)
	}

	/// Joins what the menu or the double click named, which is not necessarily
	/// what was selected before it landed.
	private func join(_ identifiers: Set<ServerChannelListEntry.ID>) {
		guard identifiers.isEmpty == false else { return }
		model.selection = identifiers
		joinSelected()
	}

	private func formattedTopic(_ topic: String) -> AttributedString {
		guard topic.isEmpty == false else { return AttributedString() }
		let formatted = (topic as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: NSFont.systemFontSize),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString()
		return AttributedString(formatted)
	}
}
