/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

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
@Suite("Channel topic sheet")
struct ChannelTopicFeatureTests {
	@Test("The sheet's copy is read from the namespaced catalogue, placeholders included")
	func contentUsesNamespacedLocalizedCopy() {
		let content = ChannelTopicContent.current(channelName: "#swift")

		#expect(content.headerTitle == "Topic for #swift:")
		#expect(content.editorAccessibilityHint == "Edit the topic. IRC text formatting is preserved.")
		#expect(content.changeButtonTitle == "Change Topic")
		#expect(content.cancelButtonTitle == "Cancel")
		#expect(content.windowTitle == "Change Topic")
		#expect(
			ChannelTopicStrings.maximumLengthMessage
				== "If you continue typing, the end of your topic may be cut off."
		)
		#expect(
			ChannelTopicStrings.maximumLengthTitle(networkName: "ExampleNet", maximumLength: 120)
				== "You have exceeded the maximum topic length defined by ExampleNet which is 120 characters"
		)
	}

	@Test("The length warning is raised once, on the first crossing of a non-zero limit")
	func modelWarnsOnlyOnceAfterCrossingNonzeroOctetLimit() {
		let model = ChannelTopicModel(formattedTopic: "1234", maximumLength: 5)

		#expect(model.formattedTopicLength == 4)
		#expect(model.updateFormattedTopic("12345") == false)
		#expect(model.updateFormattedTopic("123456"))
		#expect(model.hasPresentedMaximumLengthWarning)
		#expect(model.updateFormattedTopic("1234567") == false)

		let emojiModel = ChannelTopicModel(formattedTopic: "", maximumLength: 1)
		#expect(emojiModel.updateFormattedTopic("💬"))
		// TOPICLEN is an octet count, so an emoji is four, not two.
		#expect(emojiModel.formattedTopicLength == 4)

		let unlimitedModel = ChannelTopicModel(formattedTopic: "", maximumLength: 0)
		#expect(unlimitedModel.updateFormattedTopic(String(repeating: "x", count: 1000)) == false)
	}

	@Test("Submission flattens newlines to spaces without discarding IRC formatting")
	func submissionFlattensNewlinesWithoutDiscardingIRCFormatting() {
		let formattedTopic = "first\n\u{02}bold\nlast"
		let model = ChannelTopicModel(formattedTopic: formattedTopic, maximumLength: 0)

		#expect(model.topicForSubmission == "first \u{02}bold last")
	}

	@Test("Return submits the topic and the alternate newline command is swallowed")
	func editorCoordinatorSubmitsOnReturnAndConsumesAlternateNewlineCommand() {
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

		#expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
		#expect(submissionCount == 1)
		#expect(
			coordinator.textView(
				textView,
				doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
			)
		)
		#expect(submissionCount == 1)
		#expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))) == false)
	}

	@Test("The adapter keeps identity, the formatted topic, and the typed delegate callbacks")
	func adapterPreservesIdentityFormattedTopicAndTypedDelegateCallbacks() {
		let client = GLTTestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))
		channel.associatedClient = client
		channel.topic = "first\n\u{02}bold"

		let adapter = ChannelModifyTopicSheet(channel: channel)
		let channelPrototype: ChannelScoped = adapter
		let delegate = ChannelTopicDelegateSpy()
		adapter.delegate = delegate

		#expect(adapter.client === client)
		#expect(adapter.channel === channel)
		#expect(channelPrototype.clientId == client.uniqueIdentifier)
		#expect(channelPrototype.channelId == channel.uniqueIdentifier)
		#expect(adapter.model.formattedTopic == "first\n\u{02}bold")
		adapter.ok(nil)
		#expect(delegate.acceptedTopic == "first \u{02}bold")

		adapter.sheetDidEnd(withReturnCode: 0)
		#expect(delegate.didClose)
	}
}
