// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Owns the visual policy for AppKit menu symbols. Keeping this policy in one
/// place stops the contextual menus assembled at runtime from drifting apart.
///
/// Icons go only on the few key commands ``MenuCommand/symbolNames`` maps,
/// each group all or none. The standard commands carry none of this
/// application's, so AppKit draws its own where the system does, and every
/// image keeps the size AppKit gives menu images: none is forced here.
@MainActor
enum MenuPresentation {
	static func apply(to menu: NSMenu?) {
		guard let menu else {
			return
		}

		for item in menu.items {
			if item.image == nil,
			   let symbolName = item.command?.symbolName
			{
				item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title)
			}

			if item.hasSubmenu {
				apply(to: item.submenu)
			}
		}
	}

	static func messageReplyItems(
		messageIdentifier: String,
		nickname: String?,
		excerpt: String?,
		target: AnyObject
	) -> [NSMenuItem] {
		let context = MessageMenuContext(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt
		)

		let separator = NSMenuItem.separator()

		let reply = NSMenuItem(
			title: String(localized: .MainWindow.messageContextMenuRepliesReply),
			action: #selector(MenuActionController.replyToMessage(_:)),
			keyEquivalent: ""
		)
		reply.target = target
		reply.command = .transcriptReply
		reply.representedObject = context
		reply.image = NSImage(
			systemSymbolName: "arrowshape.turn.up.left",
			accessibilityDescription: reply.title
		)

		let react = NSMenuItem(title: String(localized: .MainWindow.messageContextMenuRepliesReact), action: nil, keyEquivalent: "")
		react.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: react.title)

		let reactMenu = NSMenu(title: react.title)

		/* The same row the reaction popover offers, so the two ways in agree. */
		for emoji in RecentReactions.row(recent: SettingsKeys.Reactions.recent.value) {
			let item = NSMenuItem(
				title: emoji,
				action: #selector(MenuActionController.reactToMessage(_:)),
				keyEquivalent: ""
			)
			item.target = target
			item.command = .transcriptReact
			item.representedObject = context.reacting(with: emoji)
			reactMenu.addItem(item)
		}

		reactMenu.addItem(.separator())

		let other = NSMenuItem(
			title: String(localized: .MainWindow.messageContextMenuRepliesOther),
			action: #selector(MenuActionController.reactToMessageWithOtherEmoji(_:)),
			keyEquivalent: ""
		)
		other.target = target
		other.command = .transcriptReact
		other.representedObject = context
		reactMenu.addItem(other)
		react.submenu = reactMenu

		return [separator, reply, react]
	}

	/** "Reply Privately": a private message to the line's sender, tagged with
	 the channel it was read in. Disabled where the server cannot carry the
	 tag, because the reply would arrive without it. */
	static func privateReplyItem(
		nickname: String,
		messageIdentifier: String?,
		excerpt: String?,
		isEnabled: Bool,
		target: AnyObject
	) -> NSMenuItem {
		let item = NSMenuItem(
			title: String(localized: .Transcript.replyPrivately),
			action: isEnabled ? #selector(MenuActionController.replyPrivatelyToMessage(_:)) : nil,
			keyEquivalent: ""
		)
		item.target = target
		item.command = .transcriptReplyPrivately
		item.isEnabled = isEnabled
		item.representedObject = MessageMenuContext(
			messageIdentifier: messageIdentifier ?? "",
			nickname: nickname,
			excerpt: excerpt
		)
		item.image = NSImage(systemSymbolName: "lock", accessibilityDescription: item.title)
		return item
	}

	/** The system's own Share item, renamed.

	 AppKit gives the standard item the title "Share" and a submenu of the
	 services; the ellipsis the application used to add promised a dialog the
	 submenu never shows. */
	static func shareMenuItem(for items: [Any]) -> NSMenuItem {
		let title = String(localized: .MainWindow.titleOfTheStandardShare)
		let menuItem: NSMenuItem

		if items.isEmpty {
			menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
			menuItem.isEnabled = false
		} else {
			let picker = NSSharingServicePicker(items: items)
			menuItem = picker.standardShareMenuItem
			menuItem.title = title
			menuItem.representedObject = picker
		}

		/* The standard item brings the system's own image; the disabled
		 stand-in draws the same symbol. */
		if menuItem.image == nil {
			menuItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: title)
		}

		return menuItem
	}
}

/// The payload carried by the reply/react items of the transcript's context
/// menu. `NSMenuItem.representedObject` is `Any?`, so this stays a class the
/// action side can cast to in one step instead of a `[String: String]` unpacked
/// by literal key.
@MainActor
final class MessageMenuContext {
	let messageIdentifier: String
	let nickname: String?
	let excerpt: String?
	let emoji: String?

	init(
		messageIdentifier: String,
		nickname: String?,
		excerpt: String?,
		emoji: String? = nil
	) {
		self.messageIdentifier = messageIdentifier
		self.nickname = nickname
		self.excerpt = excerpt
		self.emoji = emoji
	}

	/// The same message, carrying the emoji a reaction item stands for.
	func reacting(with emoji: String) -> MessageMenuContext {
		MessageMenuContext(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt,
			emoji: emoji
		)
	}
}
