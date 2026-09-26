// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

@MainActor
@Observable
final class ChannelSpotlightModel {
	var searchText = "" {
		didSet {
			guard searchText != oldValue else { return }
			refreshDisplayedResults()
		}
	}

	private(set) var displayedResults: [ChannelSpotlightSearchResult] = []
	var selectedResultID: ChannelSpotlightSearchResult.ID?

	@ObservationIgnored private var allResults: [ChannelSpotlightSearchResult] = []
	@ObservationIgnored private var restrictedSessionID: String?
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	/// The conversations the spotlight can offer.
	@ObservationIgnored private let conversations: @MainActor () -> [Conversation]
	/// The connection the main window has selected, which conversation navigation
	/// can be restricted to.
	@ObservationIgnored private let selectedSessionID: @MainActor () -> String?
	/// Shows the conversation a row names, by the identity the row carries.
	@ObservationIgnored private let selectConversation: @MainActor (ChannelSpotlightSearchResult.ID) -> Void

	/** Keeps the conversation search current while SwiftUI owns the window's
	 lifecycle. The panel is opened and closed from outside, so the state it
	 draws is what follows the session list rather than the window.

	 Everything the spotlight reaches outside itself is passed in, so a test can
	 drive it without a chat session or a window. */
	init(
		conversations: @escaping @MainActor () -> [Conversation] = {
			AppServices.chatSession?.sessions.flatMap(\.conversationList) ?? []
		},
		selectedSessionID: @escaping @MainActor () -> String? = {
			AppServices.delegate?.mainWindow.selectedSession?.uniqueIdentifier
		},
		selectConversation: @escaping @MainActor (ChannelSpotlightSearchResult.ID) -> Void = { identifier in
			/* The row holds the conversation's identity rather than the
			 conversation: one can close while the spotlight is open, and the
			 directory is what knows. */
			guard let conversation = AppServices.chatSession?.findItem(withId: identifier) as? Conversation else {
				return
			}

			AppServices.delegate.mainWindow.select(conversation)
		}
	) {
		self.conversations = conversations
		self.selectedSessionID = selectedSessionID
		self.selectConversation = selectConversation
		notifications.observe(.chatSessionListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.serverSessionConversationListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] _ in
			self?.updateSessionRestriction()
		}
		notifications.observe(.userDefaultsDidChange) { [weak self] notification in
			guard notification.userInfo?[SettingsChangeNotification.changedKeyUserInfoKey] as? String
				== SettingsKeys.Appearance.conversationNavigationIsServerSpecific.name
			else { return }
			self?.updateSessionRestriction()
		}
		reloadResults()
	}

	private func updateSessionRestriction() {
		if SettingsKeys.Appearance.conversationNavigationIsServerSpecific.value {
			restrictedSessionID = selectedSessionID() ?? ""
		} else {
			restrictedSessionID = nil
		}
		refreshDisplayedResults()
	}

	/// Moves the selection by `offset`, stopping at either end: a spotlight list
	/// is read top to bottom, and wrapping from the last match back to the first
	/// looked like the arrow key had done nothing.
	func selectRelativeResult(offset: Int) {
		guard displayedResults.isEmpty == false else { return }
		let currentIndex = selectedResultID.flatMap { selectedID in
			displayedResults.firstIndex { $0.id == selectedID }
		} ?? 0
		let nextIndex = min(max(currentIndex + offset, 0), displayedResults.count - 1)
		selectedResultID = displayedResults[nextIndex].id
	}

	func result(at index: Int) -> ChannelSpotlightSearchResult? {
		guard displayedResults.indices.contains(index) else { return nil }
		return displayedResults[index]
	}

	var selectedResult: ChannelSpotlightSearchResult? {
		guard let selectedResultID else { return displayedResults.first }
		return displayedResults.first { $0.id == selectedResultID }
	}

	private func refreshDisplayedResults() {
		displayedResults = ChannelSpotlightSearchResults.displayed(
			allResults.map { $0.scored(against: searchText) },
			restrictedToSession: restrictedSessionID
		)

		if let selectedResultID,
		   displayedResults.contains(where: { $0.id == selectedResultID })
		{
			return
		}
		selectedResultID = displayedResults.first?.id
	}

	func reloadResults() {
		var admitted: Set<ChannelSpotlightSearchResult.ID> = []
		allResults = conversations()
			.map(ChannelSpotlightSearchResult.init(conversation:))
			.filter { admitted.insert($0.id).inserted }
		updateSessionRestriction()
	}

	func select(_ result: ChannelSpotlightSearchResult?) {
		guard let result else { return }
		selectConversation(result.id)
	}

	isolated deinit {
		notifications.cancelAll()
	}
}

/** The spotlight panel, and the search it is showing.

 There is one panel, and asking for it again searches afresh rather than adding
 a second window. That is why this is observable: the scene root reads the search
 through it, so a replacement redraws the window that is already up. */
@MainActor
@Observable
final class ChannelSpotlightWindow {
	private(set) var current: ChannelSpotlightModel?

	@ObservationIgnored private let scenes: ApplicationScenes

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	func open() {
		if let current {
			current.reloadResults()
		} else {
			current = ChannelSpotlightModel()
		}
		scenes.open(ApplicationSceneID.channelSpotlight)
	}

	func didClose() {
		current = nil
	}
}
