// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents
import Foundation

/** Keeps the Spotlight index and the App Shortcut suggestions in step with the
 sidebar and the settings.

 It observes the chat session, waits for a burst of changes to settle and then
 hands the index a snapshot. Turning the setting off deletes the entries and
 withdraws the suggested conversation names. Server names are always suggested. */
@MainActor
final class ConversationIndexCoordinator: ChatSessionPresenting {
	private static let settleDelay = Duration.seconds(2)

	/// One name the system may offer as a parameter of an App Shortcut phrase.
	private struct Suggestion: Hashable {
		let id: String
		let name: String
	}

	private let index: ConversationIndex
	private let actions: any IntentActions
	private let options: @MainActor () -> ConversationIndexOptions
	private let refreshShortcuts: @MainActor () -> Void
	private var pending: Task<Void, Never>?
	/// What the system was last told, so an unchanged sidebar costs no system call.
	private var publishedSuggestions: Set<Suggestion>?

	init(
		actions: any IntentActions,
		writer: some ConversationIndexWriting = CoreSpotlightIndexWriter(),
		options: @escaping @MainActor () -> ConversationIndexOptions = ConversationIndexCoordinator.storedOptions,
		refreshShortcuts: @escaping @MainActor () -> Void = { GlasstualShortcuts.updateAppShortcutParameters() }
	) {
		index = ConversationIndex(writer: writer)
		self.actions = actions
		self.options = options
		self.refreshShortcuts = refreshShortcuts
	}

	isolated deinit {
		pending?.cancel()
	}

	static func storedOptions() -> ConversationIndexOptions {
		ConversationIndexOptions(
			indexesConversations: SettingsStores.live[SettingsKeys.Spotlight.indexConversations],
			indexesDirectMessages: SettingsStores.live[SettingsKeys.Spotlight.indexDirectMessages]
		)
	}

	func schedule() {
		pending?.cancel()
		pending = Task { [weak self] in
			try? await Task.sleep(for: Self.settleDelay)
			guard Task.isCancelled == false else { return }
			await self?.reconcile()
		}
	}

	func reconcile() async {
		let options = options()
		let servers = actions.servers()
		let conversations = actions.conversations()
		if options.indexesConversations {
			await index.apply(ConversationIndexPlan.entries(servers: servers, conversations: conversations, options: options))
		} else {
			await index.removeAll()
		}
		publishSuggestions(servers: servers, conversations: conversations, options: options)
	}

	/// Tells the system the parameter values for the App Shortcut phrases, but
	/// only when they changed. The options filter comes first, so turning the
	/// setting off also withdraws the conversation names.
	private func publishSuggestions(
		servers: [IntentServerSnapshot],
		conversations: [IntentConversationSnapshot],
		options: ConversationIndexOptions
	) {
		let suggested = ConversationIndexPlan.suggestedConversations(conversations, options: options)
		let suggestions = Set(
			servers.map { Suggestion(id: $0.id, name: $0.name) } + suggested.map { Suggestion(id: $0.id, name: $0.name) }
		)
		guard suggestions != publishedSuggestions else { return }
		publishedSuggestions = suggestions
		refreshShortcuts()
	}

	// MARK: ChatSessionPresenting

	func chatSessionListDidChange(_: ChatSession) {
		schedule()
	}

	func chatSessionSidebarDidChange(_: ChatSession) {
		schedule()
	}

	func chatSessionSettingsDidChange(_: ChatSession) {
		schedule()
	}
}
