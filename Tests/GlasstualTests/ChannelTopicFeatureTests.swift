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
	func channelModifyTopicSheet(_: ChannelModifyTopicSheet, onOk topic: String) {
		acceptedTopic = topic
	}
}

@MainActor
@Suite("Channel topic sheet")
struct ChannelTopicFeatureTests {
	@Test("The sheet's copy is read from the namespaced catalogue, placeholders included")
	func contentUsesNamespacedLocalizedCopy() {
		#expect(ChannelTopicStrings.headerTitle(channelName: "#swift") == "Topic for #swift")
		#expect(
			ChannelTopicStrings.editorAccessibilityHint
				== "Edit the topic. IRC text formatting is preserved."
		)
		#expect(ChannelTopicStrings.changeButtonTitle == "Change Topic")
		#expect(ChannelTopicStrings.cancelButtonTitle == "Cancel")
	}

	/// The sheet counts down beside the editor instead of raising an alert on
	/// the keystroke that crosses the limit, and refuses to submit past it.
	@Test("The remaining length counts down, goes negative, and gates submission")
	func remainingLengthCountsDownAndGatesSubmission() {
		let model = ChannelTopicModel(formattedTopic: "1234", maximumLength: 5)

		#expect(model.formattedTopicLength == 4)
		#expect(model.remainingLength == 1)
		#expect(model.fitsMaximumLength)
		#expect(ChannelTopicStrings.lengthFooter(remaining: 1) == "1 byte remaining")

		model.formattedTopic = "123456"
		#expect(model.remainingLength == -1)
		#expect(model.fitsMaximumLength == false)
		#expect(ChannelTopicStrings.lengthFooter(remaining: -1) == "1 byte too many")
		#expect(ChannelTopicStrings.lengthFooter(remaining: 2) == "2 bytes remaining")

		// TOPICLEN is an octet count, so an emoji is four, not two.
		let emojiModel = ChannelTopicModel(formattedTopic: "💬", maximumLength: 1)
		#expect(emojiModel.formattedTopicLength == 4)
		#expect(emojiModel.remainingLength == -3)

		// A server that names no limit has nothing to count down.
		let unlimitedModel = ChannelTopicModel(formattedTopic: "", maximumLength: 0)
		unlimitedModel.formattedTopic = String(repeating: "x", count: 1000)
		#expect(unlimitedModel.remainingLength == nil)
		#expect(unlimitedModel.fitsMaximumLength)
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
		let client = TestClient()
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
		adapter.submit()
		#expect(delegate.acceptedTopic == "first \u{02}bold")
	}

	@Test("Return cannot submit a topic above the server's UTF-8 limit")
	func returnRespectsTopicLengthLimit() {
		let client = TestClient()
		client.supportInfo.processConfigurationData("TOPICLEN=3")
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))
		channel.associatedClient = client
		let adapter = ChannelModifyTopicSheet(channel: channel)
		let delegate = ChannelTopicDelegateSpy()
		adapter.delegate = delegate
		adapter.model.formattedTopic = "💬"
		let coordinator = IRCFormattingTopicEditor(
			formattedText: Binding(get: { adapter.model.formattedTopic }, set: { adapter.model.formattedTopic = $0 }),
			accessibilityLabel: ChannelTopicStrings.headerTitle(channelName: channel.name),
			submit: adapter.submit
		).makeCoordinator()
		let editor = NSTextView()

		#expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
		#expect(delegate.acceptedTopic == nil)

		adapter.model.formattedTopic = "yes"
		#expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
		#expect(delegate.acceptedTopic == "yes")
	}
}
