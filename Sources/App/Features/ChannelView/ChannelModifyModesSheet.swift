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

import AppKit
import SwiftUI

@objc(TDCChannelModifyModesSheetDelegate)
@MainActor
public protocol ChannelModifyModesSheetDelegate: NSObjectProtocol {
	@objc(channelModifyModesSheet:onOk:)
	func channelModifyModesSheet(_ sender: ChannelModifyModesSheet, onOk modes: ChannelModeContainer)

	@objc(channelModifyModesSheetWillClose:)
	func channelModifyModesSheetWillClose(_ sender: ChannelModifyModesSheet)
}

@objc(TDCChannelModifyModesSheet)
@MainActor
public final class ChannelModifyModesSheet: SheetBase, NSWindowDelegate, TDCChannelPrototype {
	private static let contentSize = NSSize(width: 440, height: 390)

	@objc public private(set) var client: IRCClient?
	@objc public private(set) var channel: IRCChannel?
	@objc public private(set) var clientId: String?
	@objc public private(set) var channelId: String?

	let model: ChannelModesModel

	private let content: ChannelModesContent

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		guard let client = channel.associatedClient else {
			preconditionFailure("ChannelModifyModesSheet requires an associated client")
		}

		self.client = client
		self.channel = channel
		clientId = client.uniqueIdentifier
		channelId = channel.uniqueIdentifier
		content = .current(channelName: channel.name)

		let sourceModes = channel.modeInfo?.modes ?? ChannelModeContainer(client: client)
		model = ChannelModesModel(
			copying: sourceModes,
			maximumKeyLength: client.supportInfo.maximumKeyLength
		)

		super.init(window: nil)
		installSheet()
	}

	private func installSheet() {
		let rootView = ChannelModesView(
			model: model,
			content: content,
			secretKeyDidChange: { [weak self] secretKey in
				self?.secretKeyDidChange(secretKey)
			},
			userLimitDidChange: { [weak self] userLimit in
				self?.model.updateUserLimit(userLimit)
			},
			submit: { [weak self] in
				self?.ok(nil)
			},
			cancel: { [weak self] in
				self?.cancel(nil)
			}
		)
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentViewController = NSHostingController(rootView: rootView)
		hostedSheet.contentMinSize = Self.contentSize
		hostedSheet.contentMaxSize = Self.contentSize
		hostedSheet.delegate = self
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.title = content.windowTitle
		hostedSheet.titleVisibility = .hidden
		hostedSheet.titlebarAppearsTransparent = true
		hostedSheet.titlebarSeparatorStyle = .none
		sheet = hostedSheet
	}

	@objc public func start() {
		startSheet()
	}

	private func secretKeyDidChange(_ secretKey: String) {
		guard model.updateSecretKey(secretKey) else {
			return
		}

		presentMaximumKeyLengthWarning()
	}

	private func presentMaximumKeyLengthWarning() {
		guard let client else {
			return
		}

		TDCAlert.alertSheet(
			with: sheet,
			body: ChannelValidationStrings.maximumKeyLengthMessage,
			title: ChannelValidationStrings.maximumKeyLengthTitle(
				networkName: client.networkNameAlt,
				maximumLength: model.maximumKeyLength
			),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: ChannelValidationSuppressionKey.maximumSecretKeyLength.rawValue,
			suppressionText: nil,
			completionBlock: nil
		)
	}

	@IBAction override public func ok(_ sender: Any?) {
		(delegate as? ChannelModifyModesSheetDelegate)?.channelModifyModesSheet(
			self,
			onOk: model.modesForSubmission()
		)

		super.ok(sender)
	}

	@objc public func windowWillClose(_: Notification) {
		(delegate as? ChannelModifyModesSheetDelegate)?.channelModifyModesSheetWillClose(self)
	}
}
