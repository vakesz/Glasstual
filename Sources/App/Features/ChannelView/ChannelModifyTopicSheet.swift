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
public protocol ChannelModifyTopicSheetDelegate: NSObjectProtocol {
	func channelModifyTopicSheet(_ sender: ChannelModifyTopicSheet, onOk topic: String)
}

@MainActor
public final class ChannelModifyTopicSheet: MainWindowSheetSession, ChannelScoped {
	public private(set) var client: IRCClient?
	public private(set) var channel: Channel?
	public private(set) var clientId: String?
	public private(set) var channelId: String?

	let model: ChannelTopicModel

	public init(channel: Channel) {
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

	public func start() {
		startSheet()
	}

	override public func submit() {
		(delegate as? ChannelModifyTopicSheetDelegate)?.channelModifyTopicSheet(
			self,
			onOk: model.topicForSubmission
		)

		super.submit()
	}
}
