// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import Observation

struct HighlightLogRow: Identifiable, Equatable {
	let id: String
	let entry: HighlightRecord
	let conversationName: String
	let message: AttributedString
	let plainMessage: String
	let time: Date

	init(entry: HighlightRecord) {
		id = "\(entry.sessionId):\(entry.conversationId):\(entry.lineNumber)"
		self.entry = entry

		let conversation = AppServices.chatSession?.findConversation(
			withId: entry.conversationId,
			onSessionWithId: entry.sessionId
		)
		conversationName = conversation?.name ?? ApplicationStrings.unknownValue

		let line = entry.lineLogged
		let formattedMessage = if line.lineType == .action {
			String(localized: .Notifications.bodyActionWithNickname(line.nickname ?? "", line.messageBody))
		} else {
			String(
				localized: .Notifications.bodyMessageWithNickname(
					line.formattedNickname(in: conversation) ?? "",
					line.messageBody
				)
			)
		}
		let renderedMessage = (formattedMessage as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: 13),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString(string: formattedMessage)
		message = AttributedString(renderedMessage)
		plainMessage = renderedMessage.string
		time = entry.timeLogged
	}

	/// How long ago the highlight arrived, as of `now`. The table redraws
	/// this every minute.
	func timeLabel(relativeTo now: Date) -> String {
		Self.relativeTimeFormatter.localizedString(for: time, relativeTo: now)
	}

	private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.dateTimeStyle = .numeric
		return formatter
	}()

	/** The row as the pasteboard gets it.

	 The time is written out in full. "5 minutes ago" is already wrong by the
	 time it is pasted anywhere, and the table used to put exactly that on the
	 pasteboard. */
	var copyText: String {
		"\(time.formatted(date: .abbreviated, time: .shortened))\t\(conversationName)\t\(plainMessage)"
	}
}

struct HighlightLogComparator: SortComparator {
	enum Field: Hashable, Sendable {
		case conversation
		case time
	}

	let field: Field
	var order: SortOrder

	func compare(_ lhs: HighlightLogRow, _ rhs: HighlightLogRow) -> ComparisonResult {
		let result = switch field {
		case .conversation:
			lhs.conversationName.localizedCaseInsensitiveCompare(rhs.conversationName)
		case .time:
			lhs.time.compare(rhs.time)
		}

		return result.ordered(by: order)
	}
}

@Observable
final class HighlightLogModel {
	var rows: [HighlightLogRow] = []
	var selection: Set<String> = []
	var sortOrder: [HighlightLogComparator] = [
		HighlightLogComparator(field: .time, order: .reverse),
	]

	var selectedCopyItems: [String] {
		let selectedRows = rows.filter { selection.contains($0.id) }
		guard selectedRows.isEmpty == false else { return [] }
		return [selectedRows.map(\.copyText).joined(separator: "\n")]
	}

	func replace(with entries: [HighlightRecord]) {
		rows = entries.map(HighlightLogRow.init)
		selection = []
		sort(using: sortOrder)
	}

	func addEntries(_ entries: [HighlightRecord]) {
		guard entries.isEmpty == false else { return }
		rows.append(contentsOf: entries.map(HighlightLogRow.init))
		sort(using: sortOrder)
	}

	func clear() {
		rows = []
		selection = []
	}

	func sort(using order: [HighlightLogComparator]) {
		rows.sort(using: order)
	}

	func entry(withID id: String) -> HighlightRecord? {
		rows.first { $0.id == id }?.entry
	}
}

/** The highlight logs the application has open, one window per connection.

 The scene bridge installs and opens the windows; what each one is showing
 belongs to this feature, which is why the application shell no longer names a
 highlight log. */
@MainActor
final class HighlightLogWindowSessions {
	private let scenes: ApplicationScenes
	private var windows = SceneSessions<String, HighlightLogWindow>()

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	/// Opens `session`'s log, or brings the window it already has forward.
	func open(for session: ServerSession) {
		let sessionIdentifier = session.uniqueIdentifier
		_ = windows.open(sessionIdentifier) { HighlightLogWindow(session: session) }
		scenes.open(ApplicationSceneID.highlightLog, value: sessionIdentifier)
	}

	/// The log of a window that is open, and nothing more: a highlight logged
	/// while no window is showing has nowhere to go.
	func visible(for sessionIdentifier: String) -> HighlightLogWindow? {
		windows[sessionIdentifier]
	}

	/// What the window for `sessionIdentifier` shows, made on the spot for a
	/// window the system is opening on its own.
	func log(for sessionIdentifier: String) -> HighlightLogWindow? {
		if let existing = windows[sessionIdentifier] {
			return existing
		}
		guard let session = AppServices.chatSession?.findSession(withId: sessionIdentifier) else {
			return nil
		}

		return windows.open(sessionIdentifier) { HighlightLogWindow(session: session) }
	}

	/// The log of a connection that is being taken away has nothing left to jump
	/// into, so the window goes with it.
	func close(for sessionIdentifier: String) {
		guard windows.close(sessionIdentifier) != nil else { return }
		scenes.dismiss(ApplicationSceneID.highlightLog, value: sessionIdentifier)
	}

	func didClose(for sessionIdentifier: String) {
		windows.close(sessionIdentifier)
	}
}

/** One connection's logged highlights, as its own window.

 A modal sheet was the wrong shape for a table whose only purpose is to jump into
 the transcript: choosing a row had to dismiss the sheet to get there, and going
 back for the next one meant reopening it. The window stays up, the transcript
 moves behind it, and highlights logged while it is open are added as they
 arrive. */
@MainActor
@Observable
final class HighlightLogWindow: SessionScoped {
	let session: ServerSession
	let sessionId: String?

	let model = HighlightLogModel()

	init(session: ServerSession) {
		self.session = session
		sessionId = session.uniqueIdentifier
		model.replace(with: session.cachedHighlights)
	}

	var networkName: String {
		session.networkNameAlt
	}

	func addEntry(_ newEntry: HighlightRecord) {
		model.addEntries([newEntry])
	}

	func clearHighlights() {
		model.clear()
		session.clearCachedHighlights()
	}

	/** Selects the conversation the highlight was logged in and scrolls to the line.

	 The window stays open: the log exists to move around the transcript with,
	 and closing it on every jump made a second one a second trip through the
	 menu. The conversation is looked up again once the jump lands because the
	 wait gives the directory time to have destroyed it. */
	func activateHighlight(withID id: String) {
		guard let entry = model.entry(withID: id) else { return }
		let conversation = AppServices.chatSession?.findConversation(
			withId: entry.conversationId,
			onSessionWithId: entry.sessionId
		)
		guard let conversation, let transcriptController = conversation.transcriptController, let sessionId
		else { return }

		let conversationId = conversation.uniqueIdentifier
		transcriptController.jump(toLine: entry.lineNumber) { success in
			guard success else { return }
			guard let conversation = AppServices.chatSession?.findConversation(
				withId: conversationId,
				onSessionWithId: sessionId
			) else { return }

			AppServices.delegate.mainWindow.select(conversation)
		}
	}
}
