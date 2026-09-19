// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The spotlight's own behaviour — what the arrow keys do and what a chosen row
/// reports — driven through the model's injected surroundings rather than a
/// running window.
@MainActor
@Suite("Channel spotlight model")
struct ChannelSpotlightModelTests {
	private func channel(_ name: String) -> Conversation {
		Conversation(config: ConversationConfig.seed(withName: name))
	}

	private func model(
		_ conversations: [Conversation],
		selected: @escaping @MainActor (ChannelSpotlightSearchResult.ID) -> Void = { _ in }
	) -> ChannelSpotlightModel {
		ChannelSpotlightModel(
			conversations: { conversations },
			/* No window: a spotlight opened with nothing selected restricts to
				no server, which is the same answer for either setting. */
			selectedSessionID: { nil },
			selectConversation: selected
		)
	}

	@Test("Arrow keys stop at either end of the list rather than wrapping")
	func relativeSelectionClampsAtBothEnds() throws {
		let spotlight = model([channel("#swift"), channel("#swiftui"), channel("#swiftly")])
		spotlight.searchText = "swift"

		#expect(spotlight.displayedResults.count == 3)
		let first = try #require(spotlight.displayedResults.first?.id)
		let last = try #require(spotlight.displayedResults.last?.id)

		spotlight.selectedResultID = first
		spotlight.selectRelativeResult(offset: -1)
		#expect(spotlight.selectedResultID == first)

		spotlight.selectedResultID = last
		spotlight.selectRelativeResult(offset: 1)
		#expect(spotlight.selectedResultID == last)

		spotlight.selectRelativeResult(offset: -10)
		#expect(spotlight.selectedResultID == first)
	}

	@Test("Choosing a row reports the channel it names, and choosing nothing reports nothing")
	func selectionReportsTheChosenChannel() {
		var chosen: [String] = []
		let channels = [channel("#swift")]
		let spotlight = model(channels) { chosen.append($0) }
		spotlight.searchText = "swift"

		spotlight.select(nil)
		#expect(chosen.isEmpty)

		spotlight.select(spotlight.selectedResult)
		#expect(chosen == [channels[0].uniqueIdentifier])
	}

	@Test("The same channel offered twice is only a row once")
	func duplicateChannelsAreAdmittedOnce() {
		let repeated = channel("#swift")
		let spotlight = model([repeated, repeated])
		spotlight.searchText = "swift"

		#expect(spotlight.displayedResults.count == 1)
	}
}
