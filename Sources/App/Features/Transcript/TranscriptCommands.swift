// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import UniformTypeIdentifiers

private enum TranscriptContextMenuSuppressionKey: String {
	/** A key of its own rather than the one the question used to carry: the
	 recorded answer is a button, and the buttons this alert offers changed
	 sides, so a reader who once ticked "Do not ask again" for Open would have
	 been answering Cancel from then on. */
	case openExternalURL = "Open Link In External Application"
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

	init(sink: TranscriptCommandSink) {
		self.sink = sink
		super.init()
	}

	isolated deinit { openingLinkTask?.cancel() }

	func contextMenu(for transcript: TranscriptView, defaultMenuItems: [NSMenuItem]) -> NSMenu {
		let menu = NSMenu()
		for item in menuItems(
			for: transcript.takeContextMenuTarget(),
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
		return menu
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
		items.append(contentsOf: muteMenuItems(for: target.lineNickname))
		items.append(contentsOf: messageMenuItems(for: target, in: view))
		return items
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
		panel.begin { response in
			guard response == .OK, let url = panel.url else { return }
			Task {
				do {
					try await TranscriptImageExport.write(data, to: url)
				} catch {
					NSApp.presentError(error)
				}
			}
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
		guard let messageIdentifier = target.lineMessageIdentifier,
		      messageIdentifier.isEmpty == false,
		      let lineType = target.lineType,
		      Self.replyableLineTypes.contains(lineType),
		      let conversation = view.viewController?.associatedConversation,
		      conversation.isConsole == false
		else {
			return []
		}
		return sink.messageReplyItems(messageIdentifier, target.lineNickname, target.lineExcerpt)
	}

	func openWebpage(_ url: URL) {
		var openInBackground = SettingsKeys.Messages.openBrowserInBackground.value
		if NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
			openInBackground.toggle()
		}

		if LinkSchemeRules.opensDirectly(url) {
			OpenLink.open(url: url, inBackground: openInBackground)
			return
		}

		/* Handing an address to another application is the risky answer, so
		 Cancel is the one Return presses. The buttons name what they do, and
		 the address itself is the message: it is the one fact that decides
		 whether the reader wants this at all. */
		let request = AlertRequest(
			title: Self.openLinkTitle(
				applicationName: NSWorkspace.shared.nameOfApplication(opening: url) ?? ""
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
	/** The question asked before a link is handed to another application.

	 macOS does not always name the application that would open an address, and
	 a name that is missing must not be quoted as an empty one. */
	static func openLinkTitle(applicationName: String) -> String {
		applicationName.isEmpty
			? String(localized: .Transcript.openLinkInUnknownApplication)
			: String(localized: .Transcript.openLinkInApplication(applicationName))
	}
}
