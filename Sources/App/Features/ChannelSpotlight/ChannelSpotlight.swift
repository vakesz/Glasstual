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
	@ObservationIgnored private var restrictedClientID: String?
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	/// Keeps the channel search current while SwiftUI owns the window's
	/// lifecycle. The panel is opened and closed from outside, so the state it
	/// draws is what follows the client list rather than the window.
	init() {
		notifications.observe(.clientDirectoryClientListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.ClientChannelListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] _ in
			self?.updateClientRestriction()
		}
		notifications.observe(.glasstualUserDefaultsDidChange) { [weak self] notification in
			guard notification.userInfo?[PreferenceChangeNotification.changedKeyUserInfoKey] as? String
				== Preferences.Appearance.channelNavigationIsServerSpecific.name
			else { return }
			self?.updateClientRestriction()
		}
		reloadResults()
	}

	private func populate() {
		var admitted: Set<ChannelSpotlightSearchResult.ID> = []
		allResults = AppServices.clientDirectory.clientList
			.flatMap(\.channelList)
			.map(ChannelSpotlightSearchResult.init(channel:))
			.filter { admitted.insert($0.id).inserted }
		refreshDisplayedResults()
	}

	private func updateClientRestriction() {
		if Preferences.Appearance.channelNavigationIsServerSpecific.value {
			restrictedClientID = AppServices.delegate.mainWindow.selectedClient?.uniqueIdentifier ?? ""
		} else {
			restrictedClientID = nil
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
			restrictedToClient: restrictedClientID
		)

		if let selectedResultID,
		   displayedResults.contains(where: { $0.id == selectedResultID })
		{
			return
		}
		selectedResultID = displayedResults.first?.id
	}

	func reloadResults() {
		populate()
		updateClientRestriction()
	}

	func select(_ result: ChannelSpotlightSearchResult?) {
		/* The row holds the channel's identity rather than the channel: one can
		 close while the spotlight is open, and the directory is what knows. */
		guard let result,
		      let channel = AppServices.clientDirectory.findItem(withId: result.id) as? Channel
		else { return }
		AppServices.delegate.mainWindow.select(channel)
	}

	func close() {
		notifications.cancelAll()
	}

	isolated deinit {
		notifications.cancelAll()
	}
}
