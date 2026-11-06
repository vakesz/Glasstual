// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Keeps the Spotlight index in step with the sidebar and the settings.

 It observes the chat session, waits for a burst of changes to settle and then
 hands the index a snapshot. Turning the setting off deletes the entries. */
@MainActor
final class ConversationIndexCoordinator: ChatSessionPresenting {
	private static let settleDelay = Duration.seconds(2)

	private let index = ConversationIndex()
	private let actions: any IntentActions
	private let options: @MainActor () -> ConversationIndexOptions
	private var pending: Task<Void, Never>?

	init(
		actions: any IntentActions,
		options: @escaping @MainActor () -> ConversationIndexOptions = ConversationIndexCoordinator.storedOptions
	) {
		self.actions = actions
		self.options = options
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

	private func reconcile() async {
		let options = options()
		guard options.indexesConversations else {
			await index.removeAll()
			return
		}
		await index.apply(ConversationIndexPlan.entries(
			servers: actions.servers(),
			conversations: actions.conversations(),
			options: options
		))
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
