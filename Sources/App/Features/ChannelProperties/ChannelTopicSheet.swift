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

import SwiftUI

@MainActor
protocol ChannelTopicSheetDelegate: NSObjectProtocol {
	func channelModifyTopicSheet(_ sender: ChannelTopicSheet, onOk topic: String)
}

@MainActor
final class ChannelTopicSheet: SheetSession, ChannelScoped {
	private(set) var client: Client?
	private(set) var channel: Channel?
	private(set) var clientId: String?
	private(set) var channelId: String?

	let model: ChannelTopicModel

	init(channel: Channel) {
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
		(delegate as? ChannelTopicSheetDelegate)?.channelModifyTopicSheet(
			self,
			onOk: model.topicForSubmission
		)

		super.submit()
	}
}
