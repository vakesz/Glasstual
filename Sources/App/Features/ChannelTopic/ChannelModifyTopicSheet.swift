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

@objc(TDCChannelModifyTopicSheetDelegate)
@MainActor
public protocol ChannelModifyTopicSheetDelegate: NSObjectProtocol {
	@objc(channelModifyTopicSheet:onOk:)
	func channelModifyTopicSheet(_ sender: ChannelModifyTopicSheet, onOk topic: String)

	@objc(channelModifyTopicSheetWillClose:)
	func channelModifyTopicSheetWillClose(_ sender: ChannelModifyTopicSheet)
}

@objc(TDCChannelModifyTopicSheet)
@MainActor
public final class ChannelModifyTopicSheet: SheetBase, NSWindowDelegate, TDCChannelPrototype {
	private enum SuppressionKey: String {
		case maximumTopicLength = "maximum_topic_length"
	}

	private static let contentSize = NSSize(width: 600, height: 201)

	@objc public private(set) var client: IRCClient?
	@objc public private(set) var channel: IRCChannel?
	@objc public private(set) var clientId: String?
	@objc public private(set) var channelId: String?

	let model: ChannelTopicModel

	private let content: ChannelTopicContent

	@objc(initWithChannel:)
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

		TDCAlert.alertSheet(
			with: sheet,
			body: ChannelTopicStrings.maximumLengthMessage,
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

	@IBAction override public func ok(_ sender: Any?) {
		(delegate as? ChannelModifyTopicSheetDelegate)?.channelModifyTopicSheet(
			self,
			onOk: model.topicForSubmission
		)

		super.ok(sender)
	}

	@objc public func windowWillClose(_: Notification) {
		(delegate as? ChannelModifyTopicSheetDelegate)?.channelModifyTopicSheetWillClose(self)
	}
}
