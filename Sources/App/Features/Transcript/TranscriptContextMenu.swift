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

private enum TranscriptContextMenuSuppressionKey: String {
	/** A key of its own rather than the one the question used to carry: the
	 recorded answer is a button, and the buttons this alert offers changed
	 sides, so a reader who once ticked "Do not ask again" for Open would have
	 been answering Cancel from then on. */
	case openExternalURL = "open_link_in_external_application"
}

final class TranscriptContextTarget: NSObject {
	var anchorURL: String?
	var channelName: String?
	var nickname: String?
	var lineNumber: String?
	var lineMessageIdentifier: String?
	var lineType: String?
	var lineNickname: String?
	var lineExcerpt: String?
	/// The address an inline image under the pointer was fetched from.
	var inlineImageURL: String?
	/// The decoded image itself, so the menu can copy or save what is on screen
	/// rather than fetching it a second time.
	var inlineImage: NSImage?
}

@MainActor
final class TranscriptContextMenu: NSObject {
	private var openingLinkTask: Task<Void, Never>?

	isolated deinit { openingLinkTask?.cancel() }

	func contextMenu(for transcript: TranscriptView, defaultMenuItems: [NSMenuItem]) -> NSMenu {
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

	func channelNameDoubleClicked(in view: TranscriptView) {
		guard let channelName = view.takeContextMenuTarget().channelName else { return }
		AppServices.delegate.menuController?.joinChannelClicked(channelName)
	}

	func nicknameDoubleClicked(in view: TranscriptView) {
		guard let nickname = view.takeContextMenuTarget().nickname else { return }
		guard let commands = AppServices.delegate.menuController else { return }
		commands.pointedNickname = nickname
		commands.memberInChannelViewDoubleClicked(nil)
	}

	func topicBarDoubleClicked() {
		AppServices.delegate.menuController?.showChannelModifyTopicSheet(nil)
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
		AppServices.delegate.menuController?.reactToMessage(sender)
	}

	private func menuItems(
		for target: TranscriptContextTarget,
		in view: TranscriptView,
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
				from: AppServices.delegate.menuController?.transcriptChannelNameMenu,
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
	private func inlineImageMenuItems(for target: TranscriptContextTarget) -> [NSMenuItem] {
		var items: [NSMenuItem] = []
		let copy = NSMenuItem(
			title: String(localized: .Transcript.copyImage),
			action: #selector(copyInlineImage(_:)),
			keyEquivalent: ""
		)
		copy.target = self
		copy.representedObject = target
		copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: copy.title)
		items.append(copy)

		let save = NSMenuItem(
			title: String(localized: .Transcript.saveImage),
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
				title: String(localized: .Transcript.openImageLink),
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
		guard let image = (sender as? NSMenuItem)?.representedObject as? TranscriptContextTarget,
		      let copied = image.inlineImage
		else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects([copied])
	}

	@objc private func saveInlineImage(_ sender: Any?) {
		guard let target = (sender as? NSMenuItem)?.representedObject as? TranscriptContextTarget,
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
		guard let target = (sender as? NSMenuItem)?.representedObject as? TranscriptContextTarget,
		      let address = target.inlineImageURL, let url = URL(string: address)
		else { return }
		openWebpage(url)
	}

	private func linkMenuItems(for address: String) -> [NSMenuItem] {
		var items = copiedMenuItems(
			from: AppServices.delegate.menuController?.transcriptURLMenu,
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
		target: TranscriptContextTarget,
		in view: TranscriptView
	) -> [NSMenuItem]? {
		guard let channel = view.viewController?.associatedChannel, channel.isUtility == false else {
			return nil
		}
		var items = copiedMenuItems(
			from: AppServices.delegate.menuController?.userControlMenu,
			userInfo: nickname
		)
		items.append(contentsOf: messageMenuItems(for: target, in: view))
		return items
	}

	private func copiedMenuItems(from menu: NSMenu?, userInfo: String) -> [NSMenuItem] {
		menu?.items.compactMap { item in
			guard let copy = item.copy() as? NSMenuItem else { return nil }
			copy.setUserInfoString(userInfo, recursively: true)
			return copy
		} ?? []
	}

	private static let replyableLineTypes = Set(
		[LogLineType.privateMessage, .action, .notice].compactMap(LogLine.string(for:))
	)

	private func messageMenuItems(for target: TranscriptContextTarget, in view: TranscriptView) -> [NSMenuItem] {
		guard let messageIdentifier = target.lineMessageIdentifier,
		      messageIdentifier.isEmpty == false,
		      let lineType = target.lineType,
		      Self.replyableLineTypes.contains(lineType),
		      let channel = view.viewController?.associatedChannel,
		      channel.isUtility == false
		else {
			return []
		}
		return AppServices.delegate.menuController?.messageReplyItems(
			messageIdentifier: messageIdentifier,
			nickname: target.lineNickname,
			excerpt: target.lineExcerpt
		) ?? []
	}

	func openWebpage(_ url: URL) {
		var openInBackground = Preferences.Messages.openBrowserInBackground.value
		if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
			openInBackground.toggle()
		}

		if LinkParser.opensDirectly(url) {
			OpenLink.open(url: url, inBackground: openInBackground)
			return
		}

		/* Handing an address to another application is the risky answer, so
		 Cancel is the one Return presses. The buttons name what they do, and
		 the address itself is the message: it is the one fact that decides
		 whether the reader wants this at all. */
		let request = AlertRequest(
			title: TranscriptContextMenu.openLinkTitle(
				applicationName: NSWorkspace.shared.textual_nameOfApplication(toOpen: url) ?? ""
			),
			body: url.absoluteString,
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: PromptStrings.Action.open,
			suppressionKey: TranscriptContextMenuSuppressionKey.openExternalURL.rawValue
		)
		openingLinkTask?.cancel()
		openingLinkTask = Task {
			let outcome = await Alerts.run(request, on: .mainWindow)
			guard !Task.isCancelled, outcome.response == .alternate else { return }
			OpenLink.open(url: url, inBackground: openInBackground)
		}
	}
}

extension TranscriptContextMenu {
	/** The question asked before a link is handed to another application.

	 macOS does not always name the application that would open an address, and
	 a name that is missing must not be quoted as an empty one. */
	static func openLinkTitle(applicationName: String) -> String {
		applicationName.isEmpty
			? String(localized: .Transcript.openLinkInUnknownApplication)
			: String(localized: .Transcript.openLinkInApplication(applicationName))
	}
}
