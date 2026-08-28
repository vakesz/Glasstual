/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

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
final class HighlightEntryFeatureTests: XCTestCase {
	func testTypedSelectionsMapLegacyBooleansAndChannelIdentifiers() {
		XCTAssertEqual(HighlightMatchBehavior(excludesMatches: false), .include)
		XCTAssertEqual(HighlightMatchBehavior(excludesMatches: true), .exclude)
		XCTAssertFalse(HighlightMatchBehavior.include.excludesMatches)
		XCTAssertTrue(HighlightMatchBehavior.exclude.excludesMatches)
		XCTAssertNil(HighlightChannelSelection.all.channelID)
		XCTAssertEqual(HighlightChannelSelection.channel(id: "channel-a").channelID, "channel-a")
	}

	func testModelCopiesConfigurationAndPreservesKnownChannelSelection() {
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

		XCTAssertEqual(model.behavior, .exclude)
		XCTAssertEqual(model.keyword, " original ")
		XCTAssertEqual(model.channelSelection, .channel(id: "channel-a"))

		model.setBehavior(.include)
		model.updateKeyword(" replacement ")
		model.setChannelSelection(.channel(id: "channel-b"))
		let submitted = model.configurationForSubmission()

		XCTAssertTrue(source.matchIsExcluded)
		XCTAssertEqual(source.matchKeyword, " original ")
		XCTAssertEqual(source.matchChannelId, "channel-a")
		XCTAssertEqual(submitted.uniqueIdentifier, "highlight-a")
		XCTAssertFalse(submitted.matchIsExcluded)
		XCTAssertEqual(submitted.matchKeyword, "replacement")
		XCTAssertEqual(submitted.matchChannelId, "channel-b")
	}

	func testMissingAndInvalidChannelSelectionsFallBackToAllChannels() {
		let source = HighlightMatchCondition(matchKeyword: "ping", matchChannelId: "removed-channel")
		let model = HighlightEntryModel(
			configuration: source,
			channels: [HighlightEntryChannel(id: "channel-a", name: "#swift")]
		)

		XCTAssertEqual(model.channelSelection, .all)

		model.setChannelSelection(.channel(id: "unknown-channel"))
		XCTAssertEqual(model.channelSelection, .all)
		XCTAssertNil(model.configurationForSubmission().matchChannelId)
	}

	func testKeywordValidationTrimsInputAndPresentsOnlyOnSubmission() {
		let model = HighlightEntryModel(configuration: nil, channels: [])

		XCTAssertEqual(model.validationError, ApplicationStrings.requiredField)
		XCTAssertFalse(model.isValidationMessagePresented)
		XCTAssertFalse(model.validateForSubmission())
		XCTAssertTrue(model.isValidationMessagePresented)

		model.updateKeyword("  ping me  ")
		XCTAssertNil(model.validationError)
		XCTAssertFalse(model.isValidationMessagePresented)
		XCTAssertTrue(model.validateForSubmission())
		XCTAssertEqual(model.normalizedKeyword, "ping me")
		XCTAssertEqual(model.configurationForSubmission().matchKeyword, "ping me")
	}

	func testContentUsesNamespacedAndDeduplicatedLocalizedCopy() {
		let content = HighlightEntryContent.current

		XCTAssertEqual(content.title(for: .include), "Match")
		XCTAssertEqual(content.title(for: .exclude), "Exclude")
		XCTAssertEqual(content.allChannelsTitle, "All Channels")
		XCTAssertEqual(content.keywordConnector, "the keyword")
		XCTAssertEqual(content.channelConnector, "in the channel")
		XCTAssertEqual(content.saveButtonTitle, "Save")
		XCTAssertEqual(content.cancelButtonTitle, "Cancel")
		XCTAssertEqual(content.windowTitle, "Highlight Rule")
	}

	func testAdapterHostsSwiftUIAndUsesTypedDelegateCallbacks() throws {
		let source = HighlightMatchCondition(uniqueIdentifier: "highlight-a", matchKeyword: "ping")
		let channel = ChannelConfig(uniqueIdentifier: "channel-a", channelName: "#swift")
		let adapter = HighlightEntrySheet(config: source, channels: [channel])
		let delegate = HighlightEntryDelegateSpy()

		adapter.delegate = delegate

		XCTAssertEqual(NSStringFromClass(HighlightEntrySheet.self), "TDCHighlightEntrySheet")
		XCTAssertNil(Bundle.main.path(forResource: "TDCHighlightEntrySheet", ofType: "nib"))
		XCTAssertTrue(adapter.sheet.delegate === adapter)
		XCTAssertTrue(adapter.sheet.contentViewController is NSHostingController<HighlightEntryView>)
		XCTAssertFalse(adapter.sheet.styleMask.contains(.resizable))
		XCTAssertFalse(adapter.sheet.isReleasedWhenClosed)
		XCTAssertFalse(adapter.sheet.isRestorable)
		XCTAssertEqual(adapter.sheet.tabbingMode, .disallowed)
		XCTAssertEqual(adapter.sheet.contentMinSize, NSSize(width: 500, height: 150))
		XCTAssertEqual(adapter.sheet.contentMaxSize, NSSize(width: 500, height: 150))
		XCTAssertFalse(
			HighlightEntrySheet.instancesRespond(to: NSSelectorFromString("startWithChannels:"))
		)

		adapter.model.setBehavior(.exclude)
		adapter.model.updateKeyword(" mention ")
		adapter.model.setChannelSelection(.channel(id: "channel-a"))
		adapter.ok(nil)

		let savedConfiguration = try XCTUnwrap(delegate.savedConfiguration)
		XCTAssertTrue(savedConfiguration.matchIsExcluded)
		XCTAssertEqual(savedConfiguration.matchKeyword, "mention")
		XCTAssertEqual(savedConfiguration.matchChannelId, "channel-a")

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		XCTAssertTrue(delegate.didClose)
	}
}
