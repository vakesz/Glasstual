// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

struct ServerChannelListScene: Scene {
	let windows: ServerChannelListWindowSessions

	var body: some Scene {
		WindowGroup(
			String(localized: .ServerChannelList.windowGroupTitle),
			id: ApplicationSceneID.serverChannelList,
			for: String.self
		) { sessionIdentifier in
			ServerChannelListSceneRoot(
				sessionIdentifier: sessionIdentifier.wrappedValue,
				windows: windows
			)
		}
		.defaultSize(width: 720, height: 420)
		/* A table of a whole network's channels: the window has a floor, not a
		 ceiling, and the reader is the one who decides how much of it to see. */
		.windowResizability(.contentMinSize)
	}
}

private struct ServerChannelListSceneRoot: View {
	let sessionIdentifier: String?
	let windows: ServerChannelListWindowSessions

	var body: some View {
		if let sessionIdentifier,
		   let list = windows.list(for: sessionIdentifier)
		{
			ServerChannelListView(
				model: list.model,
				supportsMinimumUserCount: list.supportsMinimumUserCount,
				joinSelected: list.joinSelectedChannels,
				update: list.beginRefresh
			)
			.frame(minWidth: 600, idealWidth: 720, minHeight: 320, idealHeight: 420)
			/* The network names the window; how much of it arrived is a subtitle,
			 and it counts what the window kept rather than what the search field
			 has narrowed the table to. */
			.navigationTitle(list.networkName)
			.navigationSubtitle(
				String(localized: .ServerChannelList.publicChannelCount(list.model.keptEntryCount))
			)
			.onDisappear {
				windows.didClose(for: sessionIdentifier)
			}
		} else {
			ContentUnavailableView(
				String(localized: .ServerChannelList.noChannelList),
				systemImage: "number",
				description: Text(.ServerChannelList.noChannelListDescription)
			)
			.frame(minWidth: 600, minHeight: 320)
		}
	}
}

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
			prompt: Text(.ServerChannelList.searchChannels)
		)
	}

	private var channelTable: some View {
		ServerChannelListTable(
			model: model,
			revision: model.rowsRevision,
			selection: model.selection,
			sortOrder: model.sortOrder,
			joinSelected: joinSelected
		)
		.overlay {
			if model.rows.isEmpty {
				if model.isRefreshing || model.isFiltering {
					ProgressView(.ServerChannelList.requestingChannelList)
				} else {
					ContentUnavailableView(
						String(localized: .ServerChannelList.noPublicChannels),
						systemImage: "number",
						description: Text(.ServerChannelList.changeTheSearchOrUpdate)
					)
				}
			}
		}
		.accessibilityLabel(.ServerChannelList.publicChannelList)
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
					LabeledContent(.ServerChannelList.minimumUsers) {
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
						.accessibilityLabel(.ServerChannelList.requestingChannelList)
				}

				Button(.ServerChannelList.updateList, action: update)
					.keyboardShortcut("r", modifiers: .command)
					.disabled(model.isRefreshing)

				Button(.ServerChannelList.joinSelectedChannels, action: joinSelected)
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(model.selection.isEmpty)
			}

			if supportsMinimumUserCount {
				Text(.ServerChannelList.onlyListChannelsWithAtLeast)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
		.padding(UISpacing.wide)
	}
}
