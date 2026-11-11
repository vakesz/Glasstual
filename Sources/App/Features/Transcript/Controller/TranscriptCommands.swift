// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import UniformTypeIdentifiers

enum TranscriptContextMenuSuppressionKey: String {
	/** A key of its own rather than the one the question used to carry: the
	 recorded answer is a button, and the buttons this alert offers changed
	 sides, so a reader who once ticked "Do not ask again" for Open would have
	 been answering Cancel from then on. */
	case openExternalURL = "Open Link In External Application"

	/** The key one scheme's "Do not ask again" is recorded under.

	 Consent to hand a `ftp:` link to another application says nothing about
	 `irc:` or `webcal:`, so each scheme is asked about, and remembered,
	 separately. The scheme is lowercased so that `FTP:` and `ftp:` are the
	 same answer. */
	static func openExternalURL(scheme: String?) -> String {
		"\(openExternalURL.rawValue) (\(scheme?.lowercased() ?? ""))"
	}
}

/// The message a "Show Original Message" item looks for, and the transcript
/// that looks.
final class TranscriptOriginalMessageRequest: NSObject {
	let identifier: String
	weak var controller: TranscriptController?

	init(identifier: String, controller: TranscriptController) {
		self.identifier = identifier
		self.controller = controller
	}
}

final class TranscriptContextTarget: NSObject {
	var foldLineNumber: String?
	var anchorURL: String?
	var channelName: String?
	var nickname: String?
	var lineNumber: String?
	var lineMessageIdentifier: String?
	var lineType: String?
	var lineNickname: String?
	var lineExcerpt: String?
	/// The XDCC pack the line under the pointer offers.
	var xdccPack: XDCCPackReference?
	/// The address an inline image under the pointer was fetched from.
	var inlineImageURL: String?
	/// The decoded image itself, so the menu can copy or save what is on screen
	/// rather than fetching it a second time.
	var inlineImage: NSImage?
}

/** What the transcript can be asked to do with what the reader pointed at: the
 context menu it builds for a click, the link it opens, and the commands a
 double click on a name, a channel or the topic bar raises.

 Only two of its entry points are menus, which is why it is not named for one.
 The commands themselves belong to the window's menu controller; this is the
 transcript's side of that seam, and ``TranscriptCommandSink`` is the seam
 itself — injected, so nothing here reaches the application delegate. */
@MainActor
final class TranscriptCommands: NSObject {
	/// Where the commands this raises are carried out. Injected, so the
	/// transcript never names the window's menu controller itself.
	private let sink: TranscriptCommandSink
	private var openingLinkTask: Task<Void, Never>?
	private var deletingMessageTask: Task<Void, Never>?
	/// The picker behind the Share item of the menu that is open.
	private var sharingPicker: NSSharingServicePicker?

	init(sink: TranscriptCommandSink) {
		self.sink = sink
		super.init()
	}

	isolated deinit {
		openingLinkTask?.cancel()
		deletingMessageTask?.cancel()
	}

	func contextMenu(for transcript: TranscriptView, defaultMenuItems: [NSMenuItem]) -> NSMenu {
		let menu = NSMenu()
		let target = transcript.takeContextMenuTarget()
		for item in menuItems(
			for: target,
			in: transcript,
			defaultMenuItems: defaultMenuItems
		) {
			// NSTextView may retain its native menu; its items cannot be reparented.
			if let copy = item.copy() as? NSMenuItem {
				// AppKit does not copy the associated nickname used by member commands.
				if let nickname = item.userInfoString {
					copy.setUserInfoString(nickname, recursively: true)
				}
				menu.addItem(copy)
			}
		}
		MenuPresentation.apply(to: menu)
		addShareItem(to: menu, selection: transcript.selection, target: target, defaultMenuItems: defaultMenuItems)
		return menu
	}

	/** The system Share menu for the selected text.

	 The standard item lists the services the system offers for it. A picker
	 whose item is copied into a menu loses its services, so the item is added
	 after the copy, and the picker is held for as long as the menu can be
	 used. NSTextView's own menu can already carry a Share item, and a second
	 one would only repeat it. */
	private func addShareItem(
		to menu: NSMenu,
		selection: String?,
		target: TranscriptContextTarget,
		defaultMenuItems: [NSMenuItem]
	) {
		guard let selection, selection.isEmpty == false, target.inlineImage == nil else { return }
		let picker = NSSharingServicePicker(items: [selection])
		let shareItem = picker.standardShareMenuItem
		let alreadyOffered = defaultMenuItems.contains { $0.title == shareItem.title }
		guard alreadyOffered == false else { return }
		sharingPicker = picker
		if menu.items.last?.isSeparatorItem == false {
			menu.addItem(.separator())
		}
		menu.addItem(shareItem)
	}

	func channelNameDoubleClicked(in view: TranscriptView) {
		guard let channelName = view.takeContextMenuTarget().channelName else { return }
		sink.joinChannel(channelName)
	}

	func nicknameDoubleClicked(in view: TranscriptView) {
		guard let nickname = view.takeContextMenuTarget().nickname else { return }
		sink.openConversation(nickname)
	}

	func topicBarDoubleClicked() {
		sink.modifyTopic()
	}

	/** Reacts with the emoji a chip in the transcript stands for.

	 A chip is the reaction someone already left, so clicking it means joining
	 them; the same command the message's React menu sends is what carries it. */
	func reactionChipClicked(_ reaction: TranscriptReactionTarget) {
		sink.react(MessageMenuContext(
			messageIdentifier: reaction.messageIdentifier,
			nickname: nil,
			excerpt: nil
		).reacting(with: reaction.emoji))
	}

	private func menuItems(
		for target: TranscriptContextTarget,
		in view: TranscriptView,
		defaultMenuItems: [NSMenuItem]
	) -> [NSMenuItem] {
		if let lineNumber = target.foldLineNumber {
			return view.foldMenuItems(for: lineNumber) + muteMenuItems(for: target.lineNickname)
		}
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
			return copiedMenuItems(from: sink.channelNameMenu(), userInfo: channelName)
		}

		var items = defaultMenuItems.filter { $0.action != #selector(NSTextView.cut(_:)) }
		items.append(contentsOf: xdccMenuItems(for: target.xdccPack, session: view.viewController?.associatedSession))
		items.append(contentsOf: muteMenuItems(for: target.lineNickname))
		items.append(contentsOf: messageMenuItems(for: target, in: view))
		return items
	}

	/** Requesting the pack a bot's line offers, or asking about it.

	 Offered only while the transcript's own connection is logged in, and the
	 request goes to that connection: the title names the exact pack and bot,
	 so choosing it is the confirmation. */
	func xdccMenuItems(for pack: XDCCPackReference?, session: ServerSession?) -> [NSMenuItem] {
		guard let pack, let session, session.isLoggedIn else { return [] }
		let request = NSMenuItem(
			title: String(localized: .Transcript.requestPackFromBot(String(pack.pack), pack.bot)),
			action: #selector(requestXDCCPack(_:)),
			keyEquivalent: ""
		)
		request.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: request.title)
		request.representedObject = XDCCPackMenuRequest(pack: pack, wantsInfo: false, session: session)
		let info = NSMenuItem(
			title: String(localized: .Transcript.getPackInfo),
			action: #selector(requestXDCCPack(_:)),
			keyEquivalent: ""
		)
		info.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: info.title)
		info.representedObject = XDCCPackMenuRequest(pack: pack, wantsInfo: true, session: session)
		for item in [request, info] {
			item.target = self
		}
		return [.separator(), request, info]
	}

	/** AppKit invokes a menu item by selector, which is a runtime boundary. */
	@objc private func requestXDCCPack(_ sender: Any?) {
		guard let request = (sender as? NSMenuItem)?.representedObject as? XDCCPackMenuRequest,
		      let session = request.session
		else { return }
		sink.requestXDCCPack(session, request.pack, request.wantsInfo)
	}

	private func muteMenuItems(for nickname: String?) -> [NSMenuItem] {
		guard let nickname, nickname.isEmpty == false else { return [] }
		let items = copiedMenuItems(from: sink.memberMenu(), userInfo: nickname)
			.filter { $0.command == .muteUser || $0.command == .unmuteUser }
		return items.isEmpty ? [] : [.separator()] + items
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
		      let image = target.inlineImage
		else { return }
		let data: Data
		do {
			data = try TranscriptImageExport.pngData(from: image)
		} catch {
			NSApp.presentError(error)
			return
		}
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.png]
		panel.nameFieldStringValue = target.inlineImageURL
			.flatMap { URL(string: $0)?.deletingPathExtension().lastPathComponent }
			.flatMap { $0.isEmpty ? nil : $0 }
			.map { "\($0).png" } ?? "image.png"
		let save: @MainActor (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			Task {
				do {
					try await TranscriptImageExport.write(data, to: url)
				} catch {
					NSApp.presentError(error)
				}
			}
		}
		/* A sheet keeps the panel with the window it belongs to: a free-floating
		 panel can be left behind another application's windows. */
		if let window = NSApp.keyWindow ?? NSApp.mainWindow {
			panel.beginSheetModal(for: window, completionHandler: save)
		} else {
			panel.begin(completionHandler: save)
		}
	}

	@objc private func openInlineImageLink(_ sender: Any?) {
		guard let target = (sender as? NSMenuItem)?.representedObject as? TranscriptContextTarget,
		      let address = target.inlineImageURL, let url = URL(string: address)
		else { return }
		openWebpage(url)
	}

	private func linkMenuItems(for address: String) -> [NSMenuItem] {
		var items = copiedMenuItems(from: sink.linkMenu(), userInfo: address)
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
		guard let conversation = view.viewController?.associatedConversation, conversation.isConsole == false
		else {
			return nil
		}
		var items = copiedMenuItems(from: sink.memberMenu(), userInfo: nickname)
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
		[ChatLineKind.privateMessage, .action, .notice].compactMap(ChatLine.string(for:))
	)

	private func messageMenuItems(for target: TranscriptContextTarget, in view: TranscriptView) -> [NSMenuItem] {
		let privateReply = privateReplyItems(for: target, in: view) + originalMessageItems(for: target, in: view)
		return publicMessageMenuItems(for: target, in: view, privateReply: privateReply)
	}

	/// "Show Original Message" for a line that replies to another.
	private func originalMessageItems(for target: TranscriptContextTarget, in view: TranscriptView) -> [NSMenuItem] {
		guard let lineNumber = target.lineNumber,
		      let identifier = view.displayedLines.first(where: { $0.matches(identifier: lineNumber) })?.replyToMessageIdentifier,
		      identifier.isEmpty == false,
		      let controller = view.viewController
		else { return [] }
		let item = NSMenuItem(
			title: String(localized: .Transcript.showOriginalMessage),
			action: #selector(showOriginalMessage(_:)),
			keyEquivalent: ""
		)
		item.target = self
		item.image = NSImage(systemSymbolName: "arrow.turn.up.left", accessibilityDescription: item.title)
		item.isEnabled = controller.canRevealMessage(identifier: identifier)
		if item.isEnabled == false {
			item.action = nil
		}
		item.representedObject = TranscriptOriginalMessageRequest(identifier: identifier, controller: controller)
		return [item]
	}

	@objc private func showOriginalMessage(_ sender: Any?) {
		guard let request = (sender as? NSMenuItem)?.representedObject as? TranscriptOriginalMessageRequest else { return }
		request.controller?.showOriginalMessage(identifier: request.identifier)
	}

	/// "Reply Privately" for a channel line written by another member.
	private func privateReplyItems(for target: TranscriptContextTarget, in view: TranscriptView) -> [NSMenuItem] {
		guard let lineType = target.lineType, Self.replyableLineTypes.contains(lineType),
		      let nickname = target.lineNickname, nickname.isEmpty == false,
		      let conversation = view.viewController?.associatedConversation, conversation.isChannel,
		      let session = view.viewController?.associatedSession, session.nicknameIsMyself(nickname) == false,
		      let item = sink.privateReplyItem(nickname, target.lineMessageIdentifier, target.lineExcerpt)
		else { return [] }
		return [item]
	}

	private func publicMessageMenuItems(
		for target: TranscriptContextTarget,
		in view: TranscriptView,
		privateReply: [NSMenuItem]
	) -> [NSMenuItem] {
		guard let messageIdentifier = target.lineMessageIdentifier,
		      messageIdentifier.isEmpty == false,
		      let lineType = target.lineType,
		      Self.replyableLineTypes.contains(lineType),
		      let conversation = view.viewController?.associatedConversation,
		      conversation.isConsole == false
		else {
			return privateReply.isEmpty ? [] : [.separator()] + privateReply
		}
		let items = sink.messageReplyItems(messageIdentifier, target.lineNickname, target.lineExcerpt) + privateReply
		return items + deleteMessageItems(
			forMessage: messageIdentifier,
			by: target.lineNickname,
			in: conversation,
			view: view,
			precededBySeparator: items.isEmpty
		)
	}

	private func deleteMessageItems(
		forMessage messageIdentifier: String,
		by nickname: String?,
		in conversation: Conversation,
		view: TranscriptView,
		precededBySeparator: Bool
	) -> [NSMenuItem] {
		guard let session = view.viewController?.associatedSession,
		      TranscriptMessageDeletion.isOffered(forMessageBy: nickname, in: conversation, on: session)
		else {
			return []
		}
		let item = NSMenuItem(
			title: String(localized: .Transcript.menuDeleteMessage),
			action: #selector(deleteMessage(_:)),
			keyEquivalent: ""
		)
		item.target = self
		item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: item.title)
		item.representedObject = TranscriptMessageDeletionRequest(
			messageIdentifier: messageIdentifier,
			conversation: conversation,
			session: session,
			window: view.textView.window
		)
		return precededBySeparator ? [.separator(), item] : [item]
	}

	@objc private func deleteMessage(_ sender: Any?) {
		guard let request = (sender as? NSMenuItem)?.representedObject as? TranscriptMessageDeletionRequest else {
			return
		}
		deletingMessageTask?.cancel()
		deletingMessageTask = Task {
			guard let reason = await TranscriptMessageDeletion.confirm(in: request.window), !Task.isCancelled,
			      let session = request.session, let conversation = request.conversation
			else { return }
			session.redactMessage(
				withIdentifier: request.messageIdentifier,
				in: conversation,
				reason: reason
			)
		}
	}

	func openWebpage(_ url: URL) {
		var openInBackground = SettingsKeys.Messages.openBrowserInBackground.value
		if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
			openInBackground.toggle()
		}

		/* A link into this application comes back through the URL event, and
		 the link handler asks there before anything that needs asking. */
		if LinkSchemeRules.opensDirectly(url) || LinkSchemeRules.appSchemes.contains(url.scheme?.lowercased() ?? "") {
			OpenLink.open(url: url, inBackground: openInBackground)
			return
		}

		let request = Self.openLinkRequest(for: url)
		openingLinkTask?.cancel()
		openingLinkTask = Task {
			let outcome = await Alerts.run(request, on: .mainWindow)
			guard !Task.isCancelled, outcome.response == .alternate else { return }
			OpenLink.open(url: url, inBackground: openInBackground)
		}
	}
}

enum TranscriptImageExport {
	enum Failure: LocalizedError {
		case encoding
		var errorDescription: String? {
			String(localized: .Transcript.imageEncodingFailed)
		}
	}

	static func pngData(from image: NSImage) throws -> Data {
		guard let representation = image.tiffRepresentation,
		      let bitmap = NSBitmapImageRep(data: representation),
		      let data = bitmap.representation(using: .png, properties: [:])
		else { throw Failure.encoding }
		return data
	}

	@concurrent
	static func write(_ data: Data, to url: URL) async throws {
		try data.write(to: url, options: .atomic)
	}
}

extension TranscriptCommands {
	static func openLinkRequest(for url: URL) -> AlertRequest {
		/* Handing an address to another application is the risky answer, so
		 Cancel is the one Return presses. The buttons name what they do, and
		 the address itself is the message: it is the one fact that decides
		 whether the reader wants this at all. A link into this application is
		 asked about every time: one answer for the scheme would also answer for
		 the links that open folders and connect. */
		AlertRequest(
			title: openLinkTitle(applicationName: NSWorkspace.shared.nameOfApplication(opening: url) ?? ""),
			body: url.absoluteString,
			defaultButton: PromptStrings.Action.cancel,
			alternateButton: PromptStrings.Action.open,
			suppressionKey: LinkSchemeRules.appSchemes.contains(url.scheme?.lowercased() ?? "")
				? nil
				: TranscriptContextMenuSuppressionKey.openExternalURL(scheme: url.scheme)
		)
	}

	/** The question asked before a link is handed to another application.

	 macOS does not always name the application that would open an address, and
	 a name that is missing must not be quoted as an empty one. */
	static func openLinkTitle(applicationName: String) -> String {
		applicationName.isEmpty
			? String(localized: .Transcript.openLinkInUnknownApplication)
			: String(localized: .Transcript.openLinkInApplication(applicationName))
	}
}

/// What an XDCC menu item asks, carried on the item to its action.
final class XDCCPackMenuRequest: NSObject {
	let pack: XDCCPackReference
	let wantsInfo: Bool
	weak var session: ServerSession?

	init(pack: XDCCPackReference, wantsInfo: Bool, session: ServerSession) {
		self.pack = pack
		self.wantsInfo = wantsInfo
		self.session = session
	}
}
