/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

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

	private(set) var allResults: [ChannelSpotlightSearchResult] = []
	private(set) var displayedResults: [ChannelSpotlightSearchResult] = []
	var selectedResultID: ChannelSpotlightSearchResult.ID?

	private var restrictedClientID: String?

	func populate() {
		allResults = AppController.shared.world.clientList.flatMap { client in
			client.channelList.map(ChannelSpotlightSearchResult.init(channel:))
		}
		refreshDisplayedResults()
	}

	func updateClientRestriction() {
		if Preferences.Appearance.channelNavigationIsServerSpecific.value {
			restrictedClientID = AppController.shared.mainWindow.selectedClient?.uniqueIdentifier ?? ""
		} else {
			restrictedClientID = nil
		}
		refreshDisplayedResults()
	}

	func selectRelativeResult(offset: Int) {
		guard displayedResults.isEmpty == false else { return }
		let currentIndex = selectedResultID.flatMap { selectedID in
			displayedResults.firstIndex { $0.id == selectedID }
		} ?? 0
		let nextIndex = (currentIndex + offset + displayedResults.count) % displayedResults.count
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
		for result in allResults {
			result.recalculateDistance(with: searchText)
		}

		var admitted: Set<ChannelSpotlightSearchResult.ID> = []
		displayedResults = ChannelSpotlightSearchResults.displayed(
			allResults,
			restrictedToClient: restrictedClientID,
			distance: \.distance,
			clientID: \.clientId
		)
		.filter { admitted.insert($0.id).inserted }

		if let selectedResultID,
		   displayedResults.contains(where: { $0.id == selectedResultID })
		{
			return
		}
		selectedResultID = displayedResults.first?.id
	}
}

/// Keeps the channel search current while SwiftUI owns its window lifecycle.
@MainActor
final class ChannelSpotlightSession {
	let model = ChannelSpotlightModel()
	private let notifications = NotificationSubscriptions()

	init() {
		notifications.observe(.ircWorldClientListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.IRCClientChannelListWasModified) { [weak self] _ in
			self?.reloadResults()
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] _ in
			self?.model.updateClientRestriction()
		}
		notifications.observe(.textualUserDefaultsDidChange) { [weak self] notification in
			guard notification.userInfo?["changedKey"] as? String
				== Preferences.Appearance.channelNavigationIsServerSpecific.name
			else { return }
			self?.model.updateClientRestriction()
		}
		reloadResults()
	}

	func reloadResults() {
		model.populate()
		model.updateClientRestriction()
	}

	func select(_ result: ChannelSpotlightSearchResult?) {
		guard let channel = result?.channel else { return }
		AppController.shared.mainWindow.select(channel)
	}

	func close() {
		notifications.cancelAll()
	}

	isolated deinit {
		notifications.cancelAll()
	}
}
