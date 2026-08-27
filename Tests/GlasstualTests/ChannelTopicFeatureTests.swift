/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

@MainActor
private final class ChannelTopicDelegateSpy: NSObject, ChannelModifyTopicSheetDelegate {
	private(set) var acceptedTopic: String?
	private(set) var didClose = false

	func channelModifyTopicSheet(_: ChannelModifyTopicSheet, onOk topic: String) {
		acceptedTopic = topic
	}

	func channelModifyTopicSheetWillClose(_: ChannelModifyTopicSheet) {
		didClose = true
	}
}

@MainActor
final class ChannelTopicFeatureTests: XCTestCase {
	func testContentUsesNamespacedLocalizedCopy() {
		let content = ChannelTopicContent.current(channelName: "#swift")

		XCTAssertEqual(content.headerTitle, "Topic for #swift:")
		XCTAssertEqual(content.editorAccessibilityHint, "Edit the topic. IRC text formatting is preserved.")
		XCTAssertEqual(content.changeButtonTitle, "Change Topic")
		XCTAssertEqual(content.cancelButtonTitle, "Cancel")
		XCTAssertEqual(content.windowTitle, "Change Topic")
		XCTAssertEqual(
			ChannelTopicStrings.maximumLengthMessage,
			"If you continue typing, the end of your topic may be cut off."
		)
		XCTAssertEqual(
			ChannelTopicStrings.maximumLengthTitle(networkName: "ExampleNet", maximumLength: 120),
			"You have exceeded the maximum topic length defined by ExampleNet which is 120 characters"
		)
	}

	func testModelWarnsOnlyOnceAfterCrossingNonzeroUTF16Limit() {
		let model = ChannelTopicModel(formattedTopic: "1234", maximumLength: 5)

		XCTAssertEqual(model.formattedTopicLength, 4)
		XCTAssertFalse(model.updateFormattedTopic("12345"))
		XCTAssertTrue(model.updateFormattedTopic("123456"))
		XCTAssertTrue(model.hasPresentedMaximumLengthWarning)
		XCTAssertFalse(model.updateFormattedTopic("1234567"))

		let emojiModel = ChannelTopicModel(formattedTopic: "", maximumLength: 1)
		XCTAssertTrue(emojiModel.updateFormattedTopic("💬"))
		XCTAssertEqual(emojiModel.formattedTopicLength, 2)

		let unlimitedModel = ChannelTopicModel(formattedTopic: "", maximumLength: 0)
		XCTAssertFalse(unlimitedModel.updateFormattedTopic(String(repeating: "x", count: 1000)))
	}

	func testSubmissionFlattensNewlinesWithoutDiscardingIRCFormatting() {
		let formattedTopic = "first\n\u{02}bold\nlast"
		let model = ChannelTopicModel(formattedTopic: formattedTopic, maximumLength: 0)

		XCTAssertEqual(model.topicForSubmission, "first \u{02}bold last")
	}

	func testEditorCoordinatorSubmitsOnReturnAndConsumesAlternateNewlineCommand() {
		var formattedText = "topic"
		var submissionCount = 0
		let editor = IRCFormattingTopicEditor(
			formattedText: Binding(
				get: { formattedText },
				set: { formattedText = $0 }
			),
			accessibilityLabel: "Topic",
			submit: { submissionCount += 1 }
		)
		let coordinator = editor.makeCoordinator()
		let textView = NSTextView()

		XCTAssertTrue(
			coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
		)
		XCTAssertEqual(submissionCount, 1)
		XCTAssertTrue(
			coordinator.textView(
				textView,
				doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
			)
		)
		XCTAssertEqual(submissionCount, 1)
		XCTAssertFalse(
			coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
		)
	}

	func testRuntimeSheetContractSurvivesWithoutANib() {
		XCTAssertEqual(NSStringFromClass(ChannelModifyTopicSheet.self), "TDCChannelModifyTopicSheet")
		XCTAssertNotNil(NSProtocolFromString("TDCChannelModifyTopicSheetDelegate"))
		XCTAssertNil(Bundle.main.path(forResource: "TDCChannelModifyTopicSheet", ofType: "nib"))

		for selectorName in [
			"initWithChannel:",
			"start",
			"ok:",
			"cancel:",
			"windowWillClose:",
		] {
			XCTAssertTrue(
				ChannelModifyTopicSheet.instancesRespond(to: NSSelectorFromString(selectorName)),
				selectorName
			)
		}
	}

	func testAdapterPreservesIdentityFormattedTopicAndTypedDelegateCallbacks() {
		let client = GLTTestClient()
		let channel = Channel(configDictionary: ["channelName": "#swift"])
		channel.setValue(client, forKey: "associatedClient")
		channel.topic = "first\n\u{02}bold"

		let adapter = ChannelModifyTopicSheet(channel: channel)
		let channelPrototype: TDCChannelPrototype = adapter
		let delegate = ChannelTopicDelegateSpy()
		adapter.delegate = delegate

		XCTAssertIdentical(adapter.client, client)
		XCTAssertIdentical(adapter.channel, channel)
		XCTAssertEqual(channelPrototype.clientId, client.uniqueIdentifier)
		XCTAssertEqual(channelPrototype.channelId, channel.uniqueIdentifier)
		XCTAssertEqual(adapter.model.formattedTopic, "first\n\u{02}bold")
		XCTAssertTrue(adapter.sheet.delegate === adapter)
		XCTAssertTrue(adapter.sheet.contentViewController is NSHostingController<ChannelTopicView>)
		XCTAssertFalse(adapter.sheet.styleMask.contains(.resizable))
		XCTAssertFalse(adapter.sheet.isReleasedWhenClosed)
		XCTAssertFalse(adapter.sheet.isRestorable)
		XCTAssertEqual(adapter.sheet.tabbingMode, .disallowed)
		XCTAssertEqual(adapter.sheet.contentMinSize, NSSize(width: 600, height: 201))
		XCTAssertEqual(adapter.sheet.contentMaxSize, NSSize(width: 600, height: 201))

		adapter.ok(nil)
		XCTAssertEqual(delegate.acceptedTopic, "first \u{02}bold")

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		XCTAssertTrue(delegate.didClose)
	}
}
