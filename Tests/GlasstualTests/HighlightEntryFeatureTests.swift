/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
private final class HighlightEntryDelegateSpy: NSObject, HighlightEntrySheetDelegate {
	private(set) var savedConfiguration: HighlightMatchCondition?
	private(set) var didClose = false

	func highlightEntrySheet(_: HighlightEntrySheet, didSave configuration: HighlightMatchCondition) {
		savedConfiguration = configuration
	}

	func highlightEntrySheetDidClose(_: HighlightEntrySheet) {
		didClose = true
	}
}

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

		model.setBehavior(.include)
		model.updateKeyword(" replacement ")
		model.setChannelSelection(.channel(id: "channel-b"))
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

		model.setChannelSelection(.channel(id: "unknown-channel"))
		#expect(model.channelSelection == .all)
		#expect(model.configurationForSubmission().matchChannelId == nil)
	}

	@Test("The keyword is trimmed, and its error only shows once submission is attempted")
	func keywordValidationTrimsInputAndPresentsOnlyOnSubmission() {
		let model = HighlightEntryModel(configuration: nil, channels: [])

		#expect(model.validationError == ApplicationStrings.requiredField)
		#expect(model.isValidationMessagePresented == false)
		#expect(model.validateForSubmission() == false)
		#expect(model.isValidationMessagePresented)

		model.updateKeyword("  ping me  ")
		#expect(model.validationError == nil)
		#expect(model.isValidationMessagePresented == false)
		#expect(model.validateForSubmission())
		#expect(model.normalizedKeyword == "ping me")
		#expect(model.configurationForSubmission().matchKeyword == "ping me")
	}

	@Test("The sheet copy comes from the namespaced, deduplicated catalog entries")
	func contentUsesNamespacedAndDeduplicatedLocalizedCopy() {
		let content = HighlightEntryContent.current

		#expect(content.title(for: .include) == "Match")
		#expect(content.title(for: .exclude) == "Exclude")
		#expect(content.allChannelsTitle == "All Channels")
		#expect(content.keywordConnector == "the keyword")
		#expect(content.channelConnector == "in the channel")
		#expect(content.saveButtonTitle == "Save")
		#expect(content.cancelButtonTitle == "Cancel")
		#expect(content.windowTitle == "Highlight Rule")
	}

	@Test("The adapter hosts SwiftUI and reports through the typed delegate callbacks")
	func adapterHostsSwiftUIAndUsesTypedDelegateCallbacks() throws {
		let source = HighlightMatchCondition(uniqueIdentifier: "highlight-a", matchKeyword: "ping")
		let channel = ChannelConfig(uniqueIdentifier: "channel-a", channelName: "#swift")
		let adapter = HighlightEntrySheet(config: source, channels: [channel])
		let delegate = HighlightEntryDelegateSpy()

		adapter.delegate = delegate

		#expect(adapter.sheet.delegate === adapter)
		#expect(adapter.sheet.contentViewController is NSHostingController<HighlightEntryView>)
		#expect(adapter.sheet.styleMask.contains(.resizable) == false)
		#expect(adapter.sheet.isReleasedWhenClosed == false)
		#expect(adapter.sheet.isRestorable == false)
		#expect(adapter.sheet.tabbingMode == .disallowed)
		#expect(adapter.sheet.contentMinSize == NSSize(width: 500, height: 150))
		#expect(adapter.sheet.contentMaxSize == NSSize(width: 500, height: 150))

		adapter.model.setBehavior(.exclude)
		adapter.model.updateKeyword(" mention ")
		adapter.model.setChannelSelection(.channel(id: "channel-a"))
		adapter.ok(nil)

		let savedConfiguration = try #require(delegate.savedConfiguration)
		#expect(savedConfiguration.matchIsExcluded)
		#expect(savedConfiguration.matchKeyword == "mention")
		#expect(savedConfiguration.matchChannelId == "channel-a")

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		#expect(delegate.didClose)
	}
}
