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
import UniformTypeIdentifiers

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
	/// The address an inline image under the pointer was fetched from.
	public var inlineImageURL: String?
	/// The decoded image itself, so the menu can copy or save what is on screen
	/// rather than fetching it a second time.
	public var inlineImage: NSImage?
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

	/** Reacts with the emoji a chip in the transcript stands for.

	 A chip is the reaction someone already left, so clicking it means joining
	 them; the same command the message's React menu sends is what carries it. */
	func reactionChipClicked(_ reaction: TranscriptReactionTarget) {
		let sender = NSMenuItem()
		sender.representedObject = MessageMenuContext(
			messageIdentifier: reaction.messageIdentifier,
			nickname: nil,
			excerpt: nil
		).reacting(with: reaction.emoji)
		AppController.shared.menuController?.reactToMessage(sender)
	}

	private func menuItems(
		for target: LogPolicyTarget,
		in view: LogView,
		defaultMenuItems: [NSMenuItem]
	) -> [NSMenuItem] {
		if target.inlineImage != nil {
			return inlineImageMenuItems(for: target)
		}
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

	/** What an inline image offers on a right click.

	 An image drawn into the transcript is otherwise unreachable: it is not a
	 link the reader can copy and not text they can select, so copying it,
	 keeping it and following it back to where it came from all have to be
	 offered here. */
	private func inlineImageMenuItems(for target: LogPolicyTarget) -> [NSMenuItem] {
		var items: [NSMenuItem] = []
		let copy = NSMenuItem(
			title: TranscriptViewStrings.copyImage,
			action: #selector(copyInlineImage(_:)),
			keyEquivalent: ""
		)
		copy.target = self
		copy.representedObject = target
		copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: copy.title)
		items.append(copy)

		let save = NSMenuItem(
			title: TranscriptViewStrings.saveImage,
			action: #selector(saveInlineImage(_:)),
			keyEquivalent: ""
		)
		save.target = self
		save.representedObject = target
		save.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: save.title)
		items.append(save)

		if let address = target.inlineImageURL, URL(string: address) != nil {
			items.append(.separator())
			let open = NSMenuItem(
				title: TranscriptViewStrings.openImageLink,
				action: #selector(openInlineImageLink(_:)),
				keyEquivalent: ""
			)
			open.target = self
			open.representedObject = target
			open.image = NSImage(systemSymbolName: "safari", accessibilityDescription: open.title)
			items.append(open)
		}
		return items
	}

	/** AppKit invokes a menu item by selector, which is a runtime boundary. */
	@objc private func copyInlineImage(_ sender: Any?) {
		guard let image = (sender as? NSMenuItem)?.representedObject as? LogPolicyTarget,
		      let copied = image.inlineImage
		else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects([copied])
	}

	@objc private func saveInlineImage(_ sender: Any?) {
		guard let target = (sender as? NSMenuItem)?.representedObject as? LogPolicyTarget,
		      let image = target.inlineImage,
		      let representation = image.tiffRepresentation,
		      let bitmap = NSBitmapImageRep(data: representation),
		      let data = bitmap.representation(using: .png, properties: [:])
		else { return }
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.png]
		panel.nameFieldStringValue = target.inlineImageURL
			.flatMap { URL(string: $0)?.deletingPathExtension().lastPathComponent }
			.flatMap { $0.isEmpty ? nil : $0 }
			.map { "\($0).png" } ?? "image.png"
		panel.begin { response in
			guard response == .OK, let url = panel.url else { return }
			try? data.write(to: url, options: .atomic)
		}
	}

	@objc private func openInlineImageLink(_ sender: Any?) {
		guard let target = (sender as? NSMenuItem)?.representedObject as? LogPolicyTarget,
		      let address = target.inlineImageURL, let url = URL(string: address)
		else { return }
		openWebpage(url)
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
		if scheme == "http" || scheme == "https" || scheme == "glasstual" || scheme == "textual" {
			OpenLink.open(url: url, inBackground: openInBackground)
			return
		}

		let applicationName = NSWorkspace.shared.textual_nameOfApplication(toOpen: url) ?? ""
		/* The buttons name what they do rather than answering the title as a
		 question, which is what a reader skimming a dialog reads first. */
		let shouldOpen = Alerts.modalAlert(
			withMessage: PromptStrings.ExternalApplication.body(url: url.absoluteString),
			title: PromptStrings.ExternalApplication.title(applicationName: applicationName),
			defaultButton: PromptStrings.Action.open,
			alternateButton: PromptStrings.Action.cancel,
			suppressionKey: LogPolicySuppressionKey.openExternalURL.rawValue,
			suppressionText: nil
		)
		if shouldOpen {
			OpenLink.open(url: url, inBackground: openInBackground)
		}
	}
}
