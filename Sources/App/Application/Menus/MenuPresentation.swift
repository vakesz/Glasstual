// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Owns the visual policy for AppKit menu symbols. Keeping this policy in one
/// place stops the contextual menus assembled at runtime from drifting apart.
///
/// Contextual menus and the menu bar both get symbols, following the macOS 26
/// convention: an actionable command with a clear symbol carries it, and a
/// command without one stays blank. Items AppKit owns -- Services, the Hide
/// and Quit commands, Minimize, Zoom, Bring All to Front -- have no mapping
/// and are left to the system. The Channel and Query menus hang in the menu
/// bar and take the same symbols as their contextual copies. Whether a symbol
/// is drawn is AppKit's call, which follows the running release.
@MainActor
enum MenuPresentation {
	private static let symbolConfiguration = NSImage.SymbolConfiguration(
		pointSize: NSFont.systemFontSize,
		weight: .regular,
		scale: .medium
	)

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

			/* Visibility stays automatic: AppKit decides per release and
			 system setting whether menu images are drawn. */
			item.image = item.image?.withSymbolConfiguration(symbolConfiguration) ?? item.image

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

		for emoji in ["👍", "❤️", "😂", "😮", "😢", "👎"] {
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

		menuItem.image = NSImage(
			systemSymbolName: "square.and.arrow.up",
			accessibilityDescription: title
		)?.withSymbolConfiguration(symbolConfiguration)

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
