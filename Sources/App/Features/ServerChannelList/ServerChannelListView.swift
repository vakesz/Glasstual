// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

struct ServerChannelListScene: Scene {
	/** The list is read from a live session, so an empty window restored on the
	 next launch is not the list anybody left open. */
	static let restoresOnLaunch = false

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
		.restorationBehavior(Self.restoresOnLaunch ? .automatic : .disabled)
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

	@State private var showsFilters = false

	var body: some View {
		channelTable
			/* A list this long is rarely cut short; when it is, the window says so
			 at its foot, as a status bar would, rather than in the toolbar. */
			.safeAreaInset(edge: .bottom, spacing: 0) {
				if let notice = model.truncationNotice {
					Text(verbatim: notice)
						.font(.callout)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, UISpacing.wide)
						.padding(.vertical, UISpacing.snug)
						.background(.bar)
				}
			}
			.searchable(
				text: $model.searchString,
				placement: .toolbar,
				prompt: Text(.ServerChannelList.searchChannels)
			)
			.toolbar {
				ToolbarItemGroup(placement: .primaryAction) {
					if model.isRefreshing || model.isFiltering {
						ProgressView()
							.controlSize(.small)
							.accessibilityLabel(.ServerChannelList.requestingChannelList)
					}
					Button(.ServerChannelList.updateList, systemImage: "arrow.clockwise", action: update)
						.keyboardShortcut("r", modifiers: .command)
						.help(Text(.ServerChannelList.updateList))
						.disabled(model.isRefreshing)
						.accessibilityIdentifier(AccessibilityIdentifier.serverChannelListUpdate)
					if supportsMinimumUserCount {
						filtersButton
					}
					Button(.ServerChannelList.joinSelectedChannels, systemImage: "arrow.right.circle", action: joinSelected)
						.keyboardShortcut(.defaultAction)
						.help(Text(.ServerChannelList.joinSelectedChannels))
						.disabled(model.selection.isEmpty)
						.accessibilityIdentifier(AccessibilityIdentifier.serverChannelListJoin)
				}
			}
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

	/// The server-side size filter, behind one toolbar button that is filled
	/// while it applies, as Mail's filter button is.
	private var filtersButton: some View {
		Button(
			String(localized: .ServerChannelList.filters),
			systemImage: model.minimumUserCount.isEmpty || model.minimumUserCount == "0"
				? "line.3.horizontal.decrease.circle"
				: "line.3.horizontal.decrease.circle.fill"
		) {
			showsFilters.toggle()
		}
		.help(Text(.ServerChannelList.filters))
		.accessibilityIdentifier(AccessibilityIdentifier.serverChannelListFilters)
		.popover(isPresented: $showsFilters, arrowEdge: .bottom) {
			Form {
				Section {
					TextField(
						String(localized: .ServerChannelList.minimumUsers),
						text: Binding(get: { model.minimumUserCount }, set: model.setMinimumUserCount),
						prompt: Text(verbatim: 0.formatted())
					)
					.monospacedDigit()
					.accessibilityIdentifier(AccessibilityIdentifier.serverChannelListMinimumUsers)
				} footer: {
					Text(.ServerChannelList.onlyListChannelsWithAtLeast)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
			.formStyle(.grouped)
			.frame(width: 300)
			.fixedSize(horizontal: false, vertical: true)
		}
	}
}
