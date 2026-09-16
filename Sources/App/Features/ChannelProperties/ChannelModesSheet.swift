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
protocol ChannelModesSheetDelegate: NSObjectProtocol {
	func channelModifyModesSheet(_ sender: ChannelModesSheet, onOk modes: ChannelModeContainer)
}

@MainActor
final class ChannelModesSheet: SheetSession, ChannelScoped {
	private(set) var client: Client?
	private(set) var channel: Channel?
	private(set) var clientId: String?
	private(set) var channelId: String?

	let model: ChannelModesModel

	init(channel: Channel) {
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

	func start() {
		startSheet()
	}

	override func submit() {
		guard model.fitsMaximumKeyLength else { return }
		(delegate as? ChannelModesSheetDelegate)?.channelModifyModesSheet(
			self,
			onOk: model.modesForSubmission()
		)

		super.submit()
	}
}
