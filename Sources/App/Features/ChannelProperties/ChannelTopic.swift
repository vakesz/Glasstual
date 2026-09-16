/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ChannelTopicModel {
	var formattedTopic: String

	let maximumLength: Int

	init(formattedTopic: String, maximumLength: UInt) {
		self.formattedTopic = formattedTopic
		self.maximumLength = Int(clamping: maximumLength)
	}

	/// TOPICLEN is an octet count, so the topic is measured in UTF-8 bytes.
	var formattedTopicLength: Int {
		formattedTopic.utf8.count
	}

	/// What the sheet counts down, or `nil` where the server named no limit.
	/// Negative once the topic no longer fits, which is what disables the
	/// button and turns the footer into a warning.
	var remainingLength: Int? {
		maximumLength > 0 ? maximumLength - formattedTopicLength : nil
	}

	var fitsMaximumLength: Bool {
		(remainingLength ?? 0) >= 0
	}

	var topicForSubmission: String {
		formattedTopic.replacingOccurrences(of: "\n", with: " ")
	}

	/// What the footer under the editor says about the server's topic limit:
	/// how much room is left, or how far past it the topic already is.
	static func lengthFooter(remaining: Int) -> String {
		remaining < 0
			? String(localized: .ChannelTopic.charactersOverLimit(arg1: -remaining))
			: String(localized: .ChannelTopic.charactersRemaining(arg1: remaining))
	}
}

@MainActor
final class ChannelTopicSheet: SheetSession, ChannelScoped {
	private(set) var client: Client?
	private(set) var channel: Channel?
	private(set) var clientId: String?
	private(set) var channelId: String?

	let model: ChannelTopicModel

	/// The topic the person chose to set.
	private let onSubmitTopic: (String) -> Void

	init(channel: Channel, onSubmitTopic: @escaping (String) -> Void) {
		self.onSubmitTopic = onSubmitTopic
		let client = channel.associatedClient

		self.client = client
		self.channel = channel
		clientId = client?.uniqueIdentifier
		channelId = channel.uniqueIdentifier
		model = ChannelTopicModel(
			formattedTopic: channel.topic ?? "",
			maximumLength: client?.supportInfo.maximumTopicLength ?? 0
		)

		super.init(window: nil)
		setContent(ChannelTopicView(
			model: model,
			channelName: channel.name,
			submit: { [weak self] in self?.submit() },
			cancel: { [weak self] in self?.cancel() }
		))
	}

	func start() {
		startSheet()
	}

	override func submit() {
		guard model.fitsMaximumLength else { return }
		onSubmitTopic(model.topicForSubmission)

		super.submit()
	}
}
