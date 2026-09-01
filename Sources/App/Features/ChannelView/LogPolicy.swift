/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

private enum LogPolicySuppressionKey: String {
	case openExternalURL = "open_non_http_url_warning"
}

public final class LogPolicyTarget: NSObject {
	public var anchorURL: String?
	public var channelName: String?
	public var nickname: String?
	public var lineNumber: String?
	public var lineMessageIdentifier: String?
	public var lineType: String?
	public var lineNickname: String?
	public var lineExcerpt: String?
}

@MainActor
public final class LogPolicy: NSObject {
	func contextMenu(for transcript: LogView, defaultMenuItems: [NSMenuItem]) -> NSMenu {
		let menu = NSMenu(title: "Context Menu")
		for item in menuItems(
			for: transcript.takeContextMenuTarget(),
			in: transcript,
			defaultMenuItems: defaultMenuItems
		) {
			menu.addItem(item)
		}
		AppController.shared.menuController?.applySymbols(to: menu)
		return menu
	}

	public func channelNameDoubleClicked(in view: LogView) {
		guard let channelName = view.takeContextMenuTarget().channelName else { return }
		AppController.shared.menuController?.joinChannelClicked(channelName)
	}

	public func nicknameDoubleClicked(in view: LogView) {
		guard let nickname = view.takeContextMenuTarget().nickname else { return }
		AppController.shared.menuController?.pointedNickname = nickname
		AppController.shared.menuController?.memberInChannelViewDoubleClicked(nil)
	}

	public func topicBarDoubleClicked() {
		AppController.shared.menuController?.showChannelModifyTopicSheet(nil)
	}

	private func menuItems(
		for target: LogPolicyTarget,
		in view: LogView,
		defaultMenuItems: [NSMenuItem]
	) -> [NSMenuItem] {
		if let address = target.anchorURL {
			return linkMenuItems(for: address)
		}
		if let nickname = target.nickname {
			return nicknameMenuItems(for: nickname, target: target, in: view)
		}
		if let channelName = target.channelName {
			return copiedMenuItems(
				from: AppController.shared.menuController?.channelViewChannelNameMenu,
				userInfo: channelName
			)
		}

		var items = defaultMenuItems.filter { $0.action != #selector(NSTextView.cut(_:)) }
		items.append(contentsOf: messageMenuItems(for: target, in: view))
		return items
	}

	private func linkMenuItems(for address: String) -> [NSMenuItem] {
		var items = copiedMenuItems(
			from: AppController.shared.menuController?.channelViewURLMenu,
			userInfo: address
		)
		items.append(.separator())
		if let url = URL(string: address),
		   let share = AppController.shared.menuController?.shareMenuItem(forItems: [url])
		{
			items.append(share)
		}
		return items
	}

	private func nicknameMenuItems(
		for nickname: String,
		target: LogPolicyTarget,
		in view: LogView
	) -> [NSMenuItem] {
		guard let channel = view.viewController?.associatedChannel, channel.isUtility == false else {
			return [NSMenuItem(title: ApplicationStrings.noActionsAvailable, action: nil, keyEquivalent: "")]
		}
		var items = copiedMenuItems(
			from: AppController.shared.menuController?.userControlMenu,
			userInfo: nickname
		)
		items.append(contentsOf: messageMenuItems(for: target, in: view))
		return items
	}

	private func copiedMenuItems(from menu: NSMenu?, userInfo: String) -> [NSMenuItem] {
		menu?.items.compactMap { item in
			guard let copy = item.copy() as? NSMenuItem else { return nil }
			copy.textual_setUserInfo(userInfo, recursively: true)
			return copy
		} ?? []
	}

	private static let replyableLineTypes = Set(
		[LogLineType.privateMessage, .action, .notice].compactMap(LogLine.string(for:))
	)

	private func messageMenuItems(for target: LogPolicyTarget, in view: LogView) -> [NSMenuItem] {
		guard let messageIdentifier = target.lineMessageIdentifier,
		      messageIdentifier.isEmpty == false,
		      let lineType = target.lineType,
		      Self.replyableLineTypes.contains(lineType),
		      let channel = view.viewController?.associatedChannel,
		      channel.isUtility == false
		else {
			return []
		}
		return AppController.shared.menuController?.messageReplyMenuItems(
			forMessageIdentifier: messageIdentifier,
			nickname: target.lineNickname,
			excerpt: target.lineExcerpt
		) ?? []
	}

	public func openWebpage(_ url: URL) {
		var openInBackground = Preferences.Messages.openBrowserInBackground.value
		if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
			openInBackground.toggle()
		}

		let scheme = url.scheme?.lowercased()
		if scheme == "http" || scheme == "https" || scheme == "glasstual" {
			OpenLink.open(url: url, inBackground: openInBackground)
			return
		}

		let applicationName = NSWorkspace.shared.textual_nameOfApplication(toOpen: url) ?? ""
		let shouldOpen = Alerts.modalAlert(
			withMessage: PromptStrings.ExternalApplication.body(url: url.absoluteString),
			title: PromptStrings.ExternalApplication.title(applicationName: applicationName),
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			suppressionKey: LogPolicySuppressionKey.openExternalURL.rawValue,
			suppressionText: nil
		)
		if shouldOpen {
			OpenLink.open(url: url, inBackground: openInBackground)
		}
	}
}
