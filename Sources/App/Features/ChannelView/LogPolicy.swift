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
import CocoaExtensions
import UniformTypeIdentifiers

private enum LogPolicySuppressionKey: String {
	/** A key of its own rather than the one the question used to carry: the
	 recorded answer is a button, and the buttons this alert offers changed
	 sides, so a reader who once ticked "Do not ask again" for Open would have
	 been answering Cancel from then on. */
	case openExternalURL = "open_link_in_external_application"
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
	private var openingLinkTask: Task<Void, Never>?

	isolated deinit { openingLinkTask?.cancel() }

	func contextMenu(for transcript: LogView, defaultMenuItems: [NSMenuItem]) -> NSMenu {
		let menu = NSMenu()
		for item in menuItems(
			for: transcript.takeContextMenuTarget(),
			in: transcript,
			defaultMenuItems: defaultMenuItems
		) {
			menu.addItem(item)
		}
		MenuPresentation.apply(to: menu)
		return menu
	}

	public func channelNameDoubleClicked(in view: LogView) {
		guard let channelName = view.takeContextMenuTarget().channelName else { return }
		AppController.shared.menuController?.actionCoordinator.joinChannelClicked(channelName)
	}

	public func nicknameDoubleClicked(in view: LogView) {
		guard let nickname = view.takeContextMenuTarget().nickname else { return }
		guard let commands = AppController.shared.menuController?.actionCoordinator else { return }
		commands.pointedNickname = nickname
		commands.memberInChannelViewDoubleClicked(nil)
	}

	public func topicBarDoubleClicked() {
		AppController.shared.menuController?.actionCoordinator.showChannelModifyTopicSheet(nil)
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
		AppController.shared.menuController?.actionCoordinator.reactToMessage(sender)
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
		if let nickname = target.nickname,
		   let items = nicknameMenuItems(for: nickname, target: target, in: view)
		{
			return items
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
		if let url = URL(string: address) {
			items.append(MenuPresentation.shareMenuItem(for: [url]))
		}
		return items
	}

	/** What a right click on a nickname offers, or `nil` where the commands
	 need a conversation this view does not have.

	 Answering with a single disabled item told the reader nothing and took the
	 text view's own Copy and Look Up away with it; `nil` sends the click back
	 to those. */
	private func nicknameMenuItems(
		for nickname: String,
		target: LogPolicyTarget,
		in view: LogView
	) -> [NSMenuItem]? {
		guard let channel = view.viewController?.associatedChannel, channel.isUtility == false else {
			return nil
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
		return AppController.shared.menuController?.actionCoordinator.messageReplyItems(
			messageIdentifier: messageIdentifier,
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

		/* Handing an address to another application is the risky answer, so
		 Cancel is the one Return presses. The buttons name what they do, and
		 the address itself is the message: it is the one fact that decides
		 whether the reader wants this at all. */
		let request = AlertRequest(
			title: TranscriptViewStrings.openLinkTitle(
				applicationName: NSWorkspace.shared.textual_nameOfApplication(toOpen: url) ?? ""
			),
			body: url.absoluteString,
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: PromptStrings.Action.open,
			suppressionKey: LogPolicySuppressionKey.openExternalURL.rawValue
		)
		openingLinkTask?.cancel()
		openingLinkTask = Task {
			let outcome = await Alerts.run(request, on: .mainWindow)
			guard !Task.isCancelled, outcome.response == .alternate else { return }
			OpenLink.open(url: url, inBackground: openInBackground)
		}
	}
}
