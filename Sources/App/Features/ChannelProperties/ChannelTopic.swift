// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ChannelTopicModel {
	var formattedTopic: String

	private let maximumLength: UInt

	init(formattedTopic: String, maximumLength: UInt) {
		self.formattedTopic = formattedTopic
		self.maximumLength = maximumLength
	}

	/// The server's TOPICLEN against what the editor holds, or `nil` where no
	/// connection named one.
	var lengthLimit: ServerLengthLimit? {
		ServerLengthLimit(using: formattedTopic, maximum: maximumLength)
	}

	var fitsLengthLimit: Bool {
		lengthLimit?.isExceeded != true
	}

	/// What the footer under the editor says about the server's topic limit:
	/// how much room is left, or how far past it the topic already is.
	var lengthCaption: String? {
		guard let limit = lengthLimit else { return nil }

		return limit.isExceeded
			? String(localized: .ChannelProperties.charactersOverLimit(arg1: -limit.remaining))
			: String(localized: .ChannelProperties.charactersRemaining(arg1: limit.remaining))
	}

	var topicForSubmission: String {
		formattedTopic.replacingOccurrences(of: "\n", with: " ")
	}
}

@MainActor
final class ChannelTopicSheet: SheetSession, ChannelScoped {
	private(set) var session: ServerSession?
	private(set) var channel: Conversation?
	private(set) var sessionId: String?
	private(set) var channelId: String?

	let model: ChannelTopicModel

	/// The topic the person chose to set.
	private let onSubmitTopic: (String) -> Void

	init(channel: Conversation, onSubmitTopic: @escaping (String) -> Void) {
		self.onSubmitTopic = onSubmitTopic
		let session = channel.associatedSession

		self.session = session
		self.channel = channel
		sessionId = session?.uniqueIdentifier
		channelId = channel.uniqueIdentifier
		model = ChannelTopicModel(
			formattedTopic: channel.topic ?? "",
			maximumLength: session?.supportInfo.maximumTopicLength ?? 0
		)

		super.init(window: nil)
		setContent(ChannelTopicView(
			model: model,
			channelName: channel.name,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		))
	}

	override func submit() {
		guard model.fitsLengthLimit else { return }
		onSubmitTopic(model.topicForSubmission)

		super.submit()
	}
}

@MainActor
struct ChannelTopicView: View {
	@Bindable var model: ChannelTopicModel

	let channelName: String
	let submit: @MainActor () -> Void
	let cancel: @MainActor () -> Void

	var body: some View {
		VStack(spacing: UISpacing.wide) {
			Form {
				Section {
					ChannelTopicEditor(
						formattedText: $model.formattedTopic,
						accessibilityLabel: String(localized: .ChannelProperties.topicEditorHeading(channelName)),
						submit: submit
					)
					.frame(minHeight: 94)
					.accessibilityHint(.ChannelProperties.editorAccessibilityHint)
				} header: {
					Text(.ChannelProperties.topicEditorHeading(channelName))
				} footer: {
					/* The count replaces the alert this sheet used to raise on
					 the keystroke that crossed the limit: the answer belongs
					 beside the text being typed, not in a dialog over it. */
					if let caption = model.lengthCaption {
						Text(verbatim: caption)
							.foregroundStyle(model.fitsLengthLimit ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
					}
				}
			}
			.formStyle(.grouped)

			HStack(spacing: UISpacing.regular) {
				Spacer()

				Button(.ChannelProperties.cancelButton, action: cancel)
					.keyboardShortcut(.cancelAction)

				Button(.ChannelProperties.changeTopicButton, action: submit)
					.keyboardShortcut(.defaultAction)
					.disabled(model.fitsLengthLimit == false)
			}
		}
		.padding(SheetMetrics.margin)
		.frame(minWidth: 480, idealWidth: 600, minHeight: 260, idealHeight: 280)
	}
}
