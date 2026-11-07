// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

struct TranscriptLogViewerView: View {
	@Bindable var model: TranscriptLogViewerModel
	let openSettings: () -> Void

	/// What the log text and the search are for: reading either again is needed
	/// when this changes.
	private struct LogSelection: Hashable {
		let conversationID: String?
		let day: TranscriptDay?
	}

	private struct SearchKey: Hashable {
		let text: String
		let selection: LogSelection
	}

	private var selection: LogSelection {
		LogSelection(conversationID: model.selectedConversationID, day: model.selectedDay)
	}

	var body: some View {
		Group {
			switch model.phase {
			case .noFolder:
				ContentUnavailableView {
					Label(.TranscriptLogViewer.noFolderTitle, systemImage: "folder.badge.questionmark")
				} description: {
					Text(.TranscriptLogViewer.noFolderDescription)
				} actions: {
					Button(.TranscriptLogViewer.openSettings, action: openSettings)
				}
			case .loading:
				ProgressView()
					.accessibilityLabel(.TranscriptLogViewer.loading)
			case .ready where model.servers.isEmpty:
				ContentUnavailableView(
					String(localized: .TranscriptLogViewer.noLogsTitle),
					systemImage: "text.page",
					description: Text(.TranscriptLogViewer.noLogsDescription)
				)
			case .ready:
				browser
			}
		}
		.frame(minWidth: 760, minHeight: 420)
		.task { await model.refresh() }
		.toolbar {
			ToolbarItem {
				Button(.TranscriptLogViewer.refresh, systemImage: "arrow.clockwise") {
					Task { await model.refresh() }
				}
				.keyboardShortcut("r", modifiers: .command)
			}
		}
	}

	private var browser: some View {
		NavigationSplitView {
			conversationList
				.navigationSplitViewColumnWidth(min: 170, ideal: 220)
		} content: {
			dayList
				.navigationSplitViewColumnWidth(min: 150, ideal: 190)
		} detail: {
			logPane
		}
		.task(id: selection) { await model.loadSelectedLog() }
		.task(id: SearchKey(text: model.searchText, selection: selection)) {
			/* Typing restarts this task, so the file is searched once the user
			 pauses rather than for every character. */
			try? await Task.sleep(for: .milliseconds(250))
			guard Task.isCancelled == false else { return }
			await model.search()
		}
	}

	// MARK: Conversations and days

	private var conversationList: some View {
		List(
			selection: Binding(
				get: { model.selectedConversationID },
				set: { model.selectConversation(id: $0) }
			)
		) {
			ForEach(model.servers) { server in
				Section(server.folder.name) {
					ForEach(server.conversations) { conversation in
						Label(title(for: conversation), systemImage: symbol(for: conversation.kind))
							.tag(conversation.id)
							.accessibilityValue(kindName(conversation.kind))
					}
				}
			}
		}
		.accessibilityLabel(.TranscriptLogViewer.conversationsLabel)
	}

	private var dayList: some View {
		List(
			selection: Binding(
				get: { model.selectedDay },
				set: { model.selectDay($0) }
			)
		) {
			ForEach(model.selectedConversation?.days ?? [], id: \.self) { day in
				Text(verbatim: day.date()?.formatted(date: .complete, time: .omitted) ?? day.filename)
					.tag(day)
			}
		}
		.overlay {
			if model.selectedConversation == nil {
				ContentUnavailableView(
					String(localized: .TranscriptLogViewer.selectConversationTitle),
					systemImage: "bubble.left.and.text.bubble.right"
				)
			}
		}
		.accessibilityLabel(.TranscriptLogViewer.daysLabel)
	}

	private func title(for conversation: TranscriptLogConversation) -> String {
		conversation.kind == .console
			? String(localized: .TranscriptLogViewer.kindConsole)
			: conversation.name
	}

	private func symbol(for kind: TranscriptKind) -> String {
		switch kind {
		case .console: "terminal"
		case .channel: "number"
		case .direct: "person"
		}
	}

	private func kindName(_ kind: TranscriptKind) -> String {
		switch kind {
		case .console: String(localized: .TranscriptLogViewer.kindConsole)
		case .channel: String(localized: .TranscriptLogViewer.kindChannel)
		case .direct: String(localized: .TranscriptLogViewer.kindDirect)
		}
	}

	// MARK: The log

	private var logPane: some View {
		Group {
			if model.selectedFile == nil {
				ContentUnavailableView(
					String(localized: .TranscriptLogViewer.selectLogTitle),
					systemImage: "text.page",
					description: Text(.TranscriptLogViewer.selectLogDescription)
				)
			} else if model.logCouldNotBeRead {
				ContentUnavailableView(
					String(localized: .TranscriptLogViewer.unreadableTitle),
					systemImage: "exclamationmark.triangle",
					description: Text(.TranscriptLogViewer.unreadableDescription)
				)
			} else if model.lines.isEmpty, model.isLoadingLog == false {
				ContentUnavailableView(
					String(localized: .TranscriptLogViewer.emptyLogTitle),
					systemImage: "text.page"
				)
			} else {
				logText
			}
		}
		.searchable(text: $model.searchText, prompt: Text(.TranscriptLogViewer.searchPrompt))
		.toolbar {
			ToolbarItemGroup {
				if model.searchText.isEmpty == false {
					Text(verbatim: matchSummary)
						.foregroundStyle(.secondary)
						.monospacedDigit()
						.accessibilityLabel(matchSummary)
				}
				Button(.TranscriptLogViewer.previousMatch, systemImage: "chevron.up") {
					Task { await model.previousMatch() }
				}
				.keyboardShortcut("g", modifiers: [.command, .shift])
				.disabled(model.hasMatches == false)
				Button(.TranscriptLogViewer.nextMatch, systemImage: "chevron.down") {
					Task { await model.nextMatch() }
				}
				.keyboardShortcut("g", modifiers: .command)
				.disabled(model.hasMatches == false)
				Button(.TranscriptLogViewer.showInFinder, systemImage: "folder") {
					if let url = model.revealURL {
						NSWorkspace.shared.activateFileViewerSelecting([url])
					}
				}
				.disabled(model.revealURL == nil)
			}
		}
	}

	private var matchSummary: String {
		guard let index = model.currentMatchIndex else {
			return String(localized: .TranscriptLogViewer.noMatches)
		}
		let count = model.matchOffsets.count
		return model.matchesAreTruncated
			? String(localized: .TranscriptLogViewer.matchPositionTruncated(index + 1, count))
			: String(localized: .TranscriptLogViewer.matchPosition(index + 1, count))
	}

	private var logText: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					if model.hasEarlierLines {
						Button(.TranscriptLogViewer.loadEarlier) {
							Task { await model.loadEarlier() }
						}
						.disabled(model.isLoadingLog)
						.frame(maxWidth: .infinity)
						.padding(.vertical, UISpacing.wide)
					}
					ForEach(model.lines) { line in
						Text(highlighted(line))
							.font(.system(.body, design: .monospaced))
							.frame(maxWidth: .infinity, alignment: .leading)
							.id(line.id)
					}
				}
				.padding(UISpacing.wide)
				.textSelection(.enabled)
			}
			.defaultScrollAnchor(.bottom)
			.onChange(of: model.scrollRequest) { _, request in
				guard let request else { return }
				proxy.scrollTo(request.lineID, anchor: .center)
			}
		}
	}

	/// The line with every occurrence of the search text marked, and the line of
	/// the current match marked more strongly.
	private func highlighted(_ line: TranscriptLogLine) -> AttributedString {
		var text = AttributedString(line.text)
		let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard query.isEmpty == false else { return text }

		let isCurrent = line.id == model.currentMatchOffset
		var remaining = line.text.startIndex ..< line.text.endIndex
		while let found = line.text.range(
			of: query,
			options: [.caseInsensitive, .diacriticInsensitive],
			range: remaining
		), let marked = Range(found, in: text) {
			text[marked].backgroundColor = isCurrent ? Color.yellow : Color.yellow.opacity(0.4)
			if isCurrent {
				text[marked].foregroundColor = Color.black
			}
			remaining = found.upperBound ..< line.text.endIndex
		}

		return text
	}
}
