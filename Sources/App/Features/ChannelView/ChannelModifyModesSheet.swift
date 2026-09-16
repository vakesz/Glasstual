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
public protocol ChannelModifyModesSheetDelegate: NSObjectProtocol {
	func channelModifyModesSheet(_ sender: ChannelModifyModesSheet, onOk modes: ChannelModeContainer)
}

@MainActor
public final class ChannelModifyModesSheet: MainWindowSheetSession, ChannelScoped {
	public private(set) var client: IRCClient?
	public private(set) var channel: Channel?
	public private(set) var clientId: String?
	public private(set) var channelId: String?

	let model: ChannelModesModel

	public init(channel: Channel) {
		guard let client = channel.associatedClient else {
			preconditionFailure("ChannelModifyModesSheet requires an associated client")
		}

		self.client = client
		self.channel = channel
		clientId = client.uniqueIdentifier
		channelId = channel.uniqueIdentifier

		let sourceModes = channel.modeInfo?.modes ?? ChannelModeContainer(client: client)
		model = ChannelModesModel(
			copying: sourceModes,
			maximumKeyLength: client.supportInfo.maximumKeyLength
		)

		super.init(window: nil)
		setContent(ChannelModesView(
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
		guard model.fitsMaximumKeyLength else { return }
		(delegate as? ChannelModifyModesSheetDelegate)?.channelModifyModesSheet(
			self,
			onOk: model.modesForSubmission()
		)

		super.submit()
	}
}
