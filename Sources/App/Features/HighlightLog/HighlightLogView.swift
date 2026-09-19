// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct HighlightLogScene: Scene {
	let windows: HighlightLogWindowSessions

	var body: some Scene {
		/* Keyed by the connection, so each server's highlights get their own
		 window: a highlight is logged against one session, which is what routes
		 it to a log, and two connections would otherwise share a table. */
		WindowGroup(
			String(localized: .HighlightLog.highlightList),
			id: ApplicationSceneID.highlightLog,
			for: String.self
		) { sessionIdentifier in
			HighlightLogSceneRoot(
				sessionIdentifier: sessionIdentifier.wrappedValue,
				windows: windows
			)
		}
		.defaultSize(width: 760, height: 460)
		/* The table holds what was logged this session, and the log is the
		 session's rather than the window's: an empty table restored on the next
		 launch is not the log anybody left open. */
		.restorationBehavior(.disabled)
	}
}

private struct HighlightLogSceneRoot: View {
	let sessionIdentifier: String?
	let windows: HighlightLogWindowSessions

	var body: some View {
		if let sessionIdentifier, let log = windows.log(for: sessionIdentifier) {
			HighlightLogView(
				model: log.model,
				activate: log.activateHighlight(withID:),
				clear: log.clearHighlights
			)
			.navigationTitle(String(localized: .HighlightLog.windowTitle(log.networkName)))
			.onDisappear {
				windows.didClose(for: sessionIdentifier)
			}
		} else {
			ContentUnavailableView(
				String(localized: .HighlightLog.emptyTitle),
				systemImage: "exclamationmark.bubble",
				description: Text(.HighlightLog.emptyDescription)
			)
			.frame(minWidth: 480, minHeight: 320)
		}
	}
}

struct HighlightLogView: View {
	@Bindable var model: HighlightLogModel
	let activate: (String) -> Void
	let clear: () -> Void

	@State private var clearConfirmationIsPresented = false

	var body: some View {
		VStack(spacing: 0) {
			Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
				TableColumn(
					.HighlightLog.channel,
					sortUsing: HighlightLogComparator(field: .conversation, order: .forward)
				) { row in
					Text(verbatim: row.conversationName).lineLimit(1)
				}
				.width(min: 90, ideal: 130)

				TableColumn(String(localized: .HighlightLog.message)) { row in
					Text(row.message).lineLimit(1)
				}
				.width(min: 220, ideal: 420)

				TableColumn(
					.HighlightLog.time,
					sortUsing: HighlightLogComparator(field: .time, order: .forward)
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
						String(localized: .HighlightLog.emptyTitle),
						systemImage: "exclamationmark.bubble",
						description: Text(.HighlightLog.emptyDescription)
					)
				}
			}
			.copyable(model.selectedCopyItems)
			/* Opening the row is the table's primary action, so it is a
			 double-click, Return and the context menu at once -- which a tap
			 gesture on each cell was none of. */
			.contextMenu(forSelectionType: HighlightLogRow.ID.self) { selection in
				Button(.HighlightLog.goToMessage) { open(selection) }
					.disabled(selection.count != 1)
			} primaryAction: { selection in
				open(selection)
			}
			.onChange(of: model.sortOrder) { _, newOrder in model.sort(using: newOrder) }
			.accessibilityLabel(.HighlightLog.highlightList)

			Divider()
			HStack {
				Text(.HighlightLog.actionNote)
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button(.HighlightLog.clearList, role: .destructive) {
					clearConfirmationIsPresented = true
				}
				.disabled(model.rows.isEmpty)
			}
			.padding(UISpacing.wide)
		}
		.confirmationDialog(
			.HighlightLog.clearListConfirmationTitle,
			isPresented: $clearConfirmationIsPresented
		) {
			Button(.HighlightLog.clearList, role: .destructive, action: clear)
			Button(PromptStrings.Action.cancel, role: .cancel) {}
		} message: {
			Text(.HighlightLog.clearListConfirmationMessage)
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

	private func open(_ selection: Set<HighlightLogRow.ID>) {
		guard let id = selection.first, selection.count == 1 else { return }
		activate(id)
	}
}
