// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual

/// A window that records what the connection code asked it to draw instead of
/// drawing anything.
@MainActor
final class RecordingSessionOutput: ServerSessionPresenting {
	private(set) var selectedItems: [ChatItem] = []
	private(set) var reloadedItems: [ChatItem] = []
	private(set) var reloadedGroups: [ChatItem] = []
	private(set) var titleUpdates: [ChatItem?] = []
	private(set) var clearedItems: [ChatItem] = []
	/// Every question the protocol layer asked, in order, whatever form it
	/// would take. No window is involved, which is the point of the seam.
	private(set) var presentedAlerts: [AlertRequest] = []
	/// Where each question in ``presentedAlerts`` belongs, at the same index.
	private(set) var presentedScopes: [PromptScope] = []
	/// Answers each question in ``presentedAlerts`` at the same index, as the
	/// user would and as late as a test likes, while ``answersManually`` is on.
	private(set) var presentedAlertCompletions: [AlertCompletion] = []
	/// The sessions and conversations whose questions were withdrawn.
	private(set) var withdrawnSessions: [String] = []
	private(set) var withdrawnConversations: [String] = []
	private(set) var closedSheetSessions: [ServerSession] = []
	/// One `+b`/`+e`/`+I`/`+q` entry a window would have taken, and the list it
	/// was routed to.
	struct MaskListEntry: Equatable {
		let channelName: String
		let modeSymbol: String
		let mask: String
		let author: String?
		let date: Date?
	}

	private(set) var maskListEntries: [MaskListEntry] = []
	/// The `(channel, mode letter)` pairs an end-of-list reply was routed to.
	private(set) var maskListFinishes: [String] = []

	/// Tests can suspend the answer to exercise stale-session handling. A
	/// `true` answer is the default button, `false` the Escape button.
	var confirmation: (@MainActor (AlertRequest) async -> Bool)?
	/// Every question that was answered at once, in order.
	private(set) var responseRequests: [AlertRequest] = []
	/// The button a question is answered with at once. The default button is the safe one.
	var responseAnswer = AlertResponse.default
	/// What a question with a field is answered with at once.
	var responseText: String?
	/// Leaves every question waiting until a test answers it through
	/// ``presentedAlertCompletions``.
	var answersManually = false
	var showsMaskListSheet = false
	/// The channels whose sheets the protocol layer asked to have closed.
	private(set) var closedSheetChannelIds: [String] = []
	/// Every highlight offered to an open highlight list, in order.
	private(set) var loggedHighlights: [HighlightRecord] = []

	var selectedItem: ChatItem?
	var selectedSession: ServerSession?
	var selectedConversation: Conversation?
	var isKeyWindow = false
	var isMainWindow = false
	var visibleItems: [ChatItem] = []

	func closeSheets(for session: ServerSession) {
		closedSheetSessions.append(session)
	}

	func maskListEntryReceived(
		for _: ServerSession,
		inChannelNamed channelName: String,
		modeSymbol: String,
		mask: String,
		setBy author: String?,
		creationDate date: Date?
	) -> Bool {
		guard showsMaskListSheet else { return false }

		maskListEntries.append(MaskListEntry(
			channelName: channelName,
			modeSymbol: modeSymbol,
			mask: mask,
			author: author,
			date: date
		))

		return true
	}

	func maskListFinished(for _: ServerSession, inChannelNamed channelName: String, modeSymbol: String) -> Bool {
		guard showsMaskListSheet else { return false }

		maskListFinishes.append("\(channelName) +\(modeSymbol)")

		return true
	}

	func closeSheets(forConversationId conversationId: String) {
		closedSheetChannelIds.append(conversationId)
	}

	func highlightWasLogged(_ entry: HighlightRecord) {
		loggedHighlights.append(entry)
	}

	func selectedConversation(on session: ServerSession) -> Conversation? {
		selectedSession === session ? selectedConversation : nil
	}

	func select(_ item: ChatItem?) {
		guard let item else { return }
		selectedItems.append(item)
		selectedItem = item
	}

	func isItemSelected(_ item: ChatItem?) -> Bool {
		item != nil && selectedItem === item
	}

	func isItemVisible(_ item: ChatItem) -> Bool {
		visibleItems.contains { $0 === item }
	}

	func reloadChatItem(_ item: ChatItem) {
		reloadedItems.append(item)
	}

	func reloadChatItemGroup(_ item: ChatItem) {
		reloadedGroups.append(item)
	}

	func reloadSidebarItems(for session: ServerSession) {
		reloadedGroups.append(session)
	}

	func refreshMessageCount(for item: ChatItem) {
		reloadedItems.append(item)
	}

	func updateTitle(for item: ChatItem) {
		titleUpdates.append(item)
	}

	func updateTitle() {
		titleUpdates.append(nil)
	}

	func updateDrawingForUserInUserList(_: User) {}

	func assignMemberList(to _: Conversation) {}

	func updateMemberListVisibilityForSelection() {}

	func clearContents(of item: ChatItem) {
		clearedItems.append(item)
	}

	func destroyInputHistory(for _: ChatItem) {}
}

extension RecordingSessionOutput: PromptPresenting {
	func ask(_ request: AlertRequest, about scope: PromptScope) async -> PromptAnswer {
		presentedAlerts.append(request)
		presentedScopes.append(scope)
		if let confirmation {
			let accepted = await confirmation(request)
			return PromptAnswer(outcome: AlertOutcome(response: accepted ? .default : request.escapeButton, isSuppressed: false))
		}
		guard answersManually else {
			responseRequests.append(request)
			return PromptAnswer(outcome: AlertOutcome(response: responseAnswer, isSuppressed: false), text: responseText)
		}
		let pending = PendingAnswer()
		presentedAlertCompletions.append { pending.resume(with: PromptAnswer(outcome: $0)) }
		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				pending.wait(continuation, escape: .escape(for: request))
			}
		} onCancel: {
			Task { @MainActor in pending.resume(with: .escape(for: request)) }
		}
	}

	func withdrawPrompts(inSession sessionID: String, connectionBoundOnly _: Bool) {
		withdrawnSessions.append(sessionID)
	}

	func withdrawPrompts(inConversation conversationID: String) {
		withdrawnConversations.append(conversationID)
	}
}

/// One question the recording window was asked, waiting for a test or a
/// cancellation to answer it. Answered once.
@MainActor
private final class PendingAnswer {
	private var continuation: CheckedContinuation<PromptAnswer, Never>?
	private var answer: PromptAnswer?

	func wait(_ continuation: CheckedContinuation<PromptAnswer, Never>, escape: PromptAnswer) {
		if let answer {
			continuation.resume(returning: answer)
			return
		}
		guard Task.isCancelled == false else {
			answer = escape
			continuation.resume(returning: escape)
			return
		}
		self.continuation = continuation
	}

	func resume(with answer: PromptAnswer) {
		guard self.answer == nil else { return }
		self.answer = answer
		continuation?.resume(returning: answer)
		continuation = nil
	}
}
