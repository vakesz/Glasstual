// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Channel topic sheet")
struct ChannelTopicFeatureTests {
	@Test("The sheet's copy is read from the namespaced catalogue, placeholders included")
	func contentUsesNamespacedLocalizedCopy() {
		#expect(String(localized: .ChannelProperties.topicEditorHeading("#swift")) == "Topic for #swift")
		#expect(
			String(localized: .ChannelProperties.editorAccessibilityHint)
				== "Edit the topic. IRC text formatting is preserved."
		)
		#expect(String(localized: .ChannelProperties.changeTopicButton) == "Change Topic")
		#expect(String(localized: .ChannelProperties.cancelButton) == "Cancel")
	}

	/// The sheet counts down beside the editor instead of raising an alert on
	/// the keystroke that crosses the limit, and refuses to submit past it.
	@Test("The remaining length counts down, goes negative, and gates submission")
	func remainingLengthCountsDownAndGatesSubmission() {
		let model = ChannelTopicModel(formattedTopic: "1234", maximumLength: 5)

		#expect(model.lengthLimit?.used == 4)
		#expect(model.lengthLimit?.remaining == 1)
		#expect(model.fitsLengthLimit)
		#expect(model.lengthCaption == "1 byte remaining")

		model.formattedTopic = "123456"
		#expect(model.lengthLimit?.remaining == -1)
		#expect(model.fitsLengthLimit == false)
		#expect(model.lengthCaption == "1 byte too many")

		model.formattedTopic = "123"
		#expect(model.lengthCaption == "2 bytes remaining")

		// TOPICLEN is an octet count, so an emoji is four, not two.
		let emojiModel = ChannelTopicModel(formattedTopic: "💬", maximumLength: 1)
		#expect(emojiModel.lengthLimit?.used == 4)
		#expect(emojiModel.lengthLimit?.remaining == -3)

		// A server that names no limit has nothing to count down.
		let unlimitedModel = ChannelTopicModel(formattedTopic: "", maximumLength: 0)
		unlimitedModel.formattedTopic = String(repeating: "x", count: 1000)
		#expect(unlimitedModel.lengthLimit == nil)
		#expect(unlimitedModel.lengthCaption == nil)
		#expect(unlimitedModel.fitsLengthLimit)
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
		let editor = ChannelTopicEditor(
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

	@Test("The sheet keeps identity and the formatted topic, and reports what it accepted")
	func sheetPreservesIdentityFormattedTopicAndReportsTheAcceptedTopic() {
		let session = TestServerSession()
		let channel = Conversation(config: ConversationConfig(name: "#swift"))
		channel.associatedSession = session
		channel.topic = "first\n\u{02}bold"

		var acceptedTopic: String?
		let adapter = ChannelTopicSheet(channel: channel) { acceptedTopic = $0 }
		let channelPrototype: ChannelScoped = adapter

		#expect(adapter.session === session)
		#expect(adapter.channel === channel)
		#expect(channelPrototype.sessionId == session.uniqueIdentifier)
		#expect(channelPrototype.channelId == channel.uniqueIdentifier)
		#expect(adapter.model.formattedTopic == "first\n\u{02}bold")
		adapter.submit()
		#expect(acceptedTopic == "first \u{02}bold")
	}

	@Test("Return cannot submit a topic above the server's UTF-8 limit")
	func returnRespectsTopicLengthLimit() {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("TOPICLEN=3")
		let channel = Conversation(config: ConversationConfig(name: "#swift"))
		channel.associatedSession = session
		var acceptedTopic: String?
		let adapter = ChannelTopicSheet(channel: channel) { acceptedTopic = $0 }
		adapter.model.formattedTopic = "💬"
		let coordinator = ChannelTopicEditor(
			formattedText: Binding(get: { adapter.model.formattedTopic }, set: { adapter.model.formattedTopic = $0 }),
			accessibilityLabel: String(localized: .ChannelProperties.topicEditorHeading(channel.name)),
			submit: adapter.submit
		).makeCoordinator()
		let editor = NSTextView()

		#expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
		#expect(acceptedTopic == nil)

		adapter.model.formattedTopic = "yes"
		#expect(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
		#expect(acceptedTopic == "yes")
	}
}
