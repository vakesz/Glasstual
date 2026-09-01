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

	func channelModifyTopicSheetWillClose(_ sender: ChannelModifyTopicSheet)
}

@MainActor
public final class ChannelModifyTopicSheet: MainWindowSheetSession, ChannelScoped {
	private enum SuppressionKey: String {
		case maximumTopicLength = "maximum_topic_length"
	}

	public private(set) var client: IRCClient?
	public private(set) var channel: IRCChannel?
	public private(set) var clientId: String?
	public private(set) var channelId: String?

	let model: ChannelTopicModel

	private let content: ChannelTopicContent

	public init(channel: IRCChannel) {
		let client = channel.associatedClient

		self.client = client
		self.channel = channel
		clientId = client?.uniqueIdentifier
		channelId = channel.uniqueIdentifier
		content = .current(channelName: channel.name)
		model = ChannelTopicModel(
			formattedTopic: channel.topic ?? "",
			maximumLength: client?.supportInfo.maximumTopicLength ?? 0
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = ChannelTopicView(
			model: model,
			content: content,
			topicDidChange: { [weak self] topic in
				self?.topicDidChange(topic)
			},
			submit: { [weak self] in
				self?.ok(nil)
			},
			cancel: { [weak self] in
				self?.cancel(nil)
			}
		)
		setContent(rootView.frame(width: 600, height: 201))
	}

	public func start() {
		startSheet()
	}

	private func topicDidChange(_ topic: String) {
		guard model.updateFormattedTopic(topic) else {
			return
		}

		presentMaximumTopicLengthWarning()
	}

	private func presentMaximumTopicLengthWarning() {
		guard let client else {
			return
		}

		Alerts.alert(
			withMessage: ChannelTopicStrings.maximumLengthMessage,
			title: ChannelTopicStrings.maximumLengthTitle(
				networkName: client.networkNameAlt,
				maximumLength: model.maximumLength
			),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: SuppressionKey.maximumTopicLength.rawValue,
			suppressionText: nil,
			completionBlock: nil
		)
	}

	override public func ok(_ sender: Any?) {
		(delegate as? ChannelModifyTopicSheetDelegate)?.channelModifyTopicSheet(
			self,
			onOk: model.topicForSubmission
		)

		super.ok(sender)
	}

	override public func sheetDidEnd(withReturnCode _: Int) {
		(delegate as? ChannelModifyTopicSheetDelegate)?.channelModifyTopicSheetWillClose(self)
	}
}
