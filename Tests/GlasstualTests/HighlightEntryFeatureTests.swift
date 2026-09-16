/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Highlight entry sheet")
struct HighlightEntryFeatureTests {
	@Test("The typed selections map the legacy booleans and channel identifiers")
	func typedSelectionsMapLegacyBooleansAndChannelIdentifiers() {
		#expect(HighlightMatchBehavior(excludesMatches: false) == .include)
		#expect(HighlightMatchBehavior(excludesMatches: true) == .exclude)
		#expect(HighlightMatchBehavior.include.excludesMatches == false)
		#expect(HighlightMatchBehavior.exclude.excludesMatches)
		#expect(HighlightChannelSelection.all.channelID == nil)
		#expect(HighlightChannelSelection.channel(id: "channel-a").channelID == "channel-a")
	}

	@Test("Editing the model leaves the source configuration untouched until submission")
	func modelCopiesConfigurationAndPreservesKnownChannelSelection() {
		let source = HighlightMatchCondition(
			uniqueIdentifier: "highlight-a",
			matchKeyword: " original ",
			matchChannelId: "channel-a",
			matchIsExcluded: true
		)
		let model = HighlightEntryModel(
			configuration: source,
			channels: [
				HighlightEntryChannel(id: "channel-a", name: "#swift"),
				HighlightEntryChannel(id: "channel-b", name: "#macos"),
			]
		)

		#expect(model.behavior == .exclude)
		#expect(model.keyword == " original ")
		#expect(model.channelSelection == .channel(id: "channel-a"))

		model.behavior = .include
		model.keyword = " replacement "
		model.channelSelection = .channel(id: "channel-b")
		let submitted = model.configurationForSubmission()

		#expect(source.matchIsExcluded)
		#expect(source.matchKeyword == " original ")
		#expect(source.matchChannelId == "channel-a")
		#expect(submitted.uniqueIdentifier == "highlight-a")
		#expect(submitted.matchIsExcluded == false)
		#expect(submitted.matchKeyword == "replacement")
		#expect(submitted.matchChannelId == "channel-b")
	}

	@Test("A channel the client no longer has falls back to every channel")
	func missingAndInvalidChannelSelectionsFallBackToAllChannels() {
		let source = HighlightMatchCondition(matchKeyword: "ping", matchChannelId: "removed-channel")
		let model = HighlightEntryModel(
			configuration: source,
			channels: [HighlightEntryChannel(id: "channel-a", name: "#swift")]
		)

		#expect(model.channelSelection == .all)

		model.channelSelection = .channel(id: "unknown-channel")
		#expect(model.channelSelection == .all)
		#expect(model.configurationForSubmission().matchChannelId == nil)
	}

	/** A new rule opens on an empty keyword, which is not a keyword — but the
	 field had a red border around it before anything had been typed into it.
	 The refusal waits for a save to be refused, and then follows the field. */
	@Test("The keyword is trimmed, and its message only shows once a save is refused")
	func keywordValidationTrimsInputAndPresentsOnlyOnSubmission() {
		let model = HighlightEntryModel(configuration: nil, channels: [])

		#expect(model.validationError == ApplicationStrings.requiredField)
		#expect(model.validationMessage == nil)
		#expect(model.validateForSubmission() == false)
		#expect(model.validationMessage == ApplicationStrings.requiredField)

		model.keyword = "  ping me  "
		#expect(model.validationError == nil)
		#expect(model.validationMessage == nil)
		#expect(model.validateForSubmission())
		#expect(model.normalizedKeyword == "ping me")
		#expect(model.configurationForSubmission().matchKeyword == "ping me")
	}

	@Test("The sheet copy comes from the namespaced, deduplicated catalog entries")
	func sheetUsesNamespacedAndDeduplicatedLocalizedCopy() {
		#expect(String(localized: HighlightMatchBehavior.include.title) == "Match")
		#expect(String(localized: HighlightMatchBehavior.exclude.title) == "Exclude")
		#expect(String(localized: .ServerProperties.allChannels) == "All Channels")
		#expect(String(localized: .HighlightEntry.windowTitle) == "Highlight Rule")
		#expect(String(localized: .HighlightEntry.matchTypeLabel) == "Match Type")
		#expect(String(localized: .HighlightEntry.keywordLabel) == "Keyword")
		#expect(String(localized: .HighlightEntry.channelLabel) == "Channel")
	}

	@Test("The sheet reports the rule it accepted")
	func sheetReportsTheAcceptedRule() throws {
		let source = HighlightMatchCondition(uniqueIdentifier: "highlight-a", matchKeyword: "ping")
		let channel = ChannelConfig(uniqueIdentifier: "channel-a", channelName: "#swift")
		var saved: HighlightMatchCondition?
		let adapter = HighlightEntrySheet(config: source, channels: [channel]) { saved = $0 }

		adapter.model.behavior = .exclude
		adapter.model.keyword = " mention "
		adapter.model.channelSelection = .channel(id: "channel-a")
		adapter.submit()

		let savedConfiguration = try #require(saved)
		#expect(savedConfiguration.matchIsExcluded)
		#expect(savedConfiguration.matchKeyword == "mention")
		#expect(savedConfiguration.matchChannelId == "channel-a")
	}
}
