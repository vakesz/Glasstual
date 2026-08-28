/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit

/// Owns the visual policy for AppKit menu symbols. Keeping this policy in one
/// place prevents nib menus and menus assembled at runtime from drifting.
@MainActor
public enum MenuPresentation {
	private static let symbolConfiguration = NSImage.SymbolConfiguration(
		pointSize: NSFont.systemFontSize,
		weight: .regular,
		scale: .medium
	)
	/// One stable instance lets repeated passes distinguish padding from a
	/// real symbol. A transparent bitmap is treated as no image on macOS 26.
	private static let symbolSpacer: NSImage? = {
		let configuration = symbolConfiguration.applying(
			NSImage.SymbolConfiguration(paletteColors: [.clear])
		)
		guard let image = NSImage(
			systemSymbolName: "circle",
			accessibilityDescription: nil
		)?.withSymbolConfiguration(configuration) else {
			return nil
		}

		image.isTemplate = false

		return image
	}()

	static func symbolName(forTag tag: Int) -> String? {
		MenuCommand(rawValue: tag)?.symbolName
	}

	static var symbolMappings: [MenuCommand: String] {
		MenuCommand.symbolNames
	}

	public static func apply(to menu: NSMenu?) {
		apply(symbolConfiguration, to: menu)
	}

	public static func messageReplyItems(
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
		separator.command = .webReplySeparator

		let reply = NSMenuItem(
			title: MessageMenuStrings.reply,
			action: #selector(TXMenuController.replyToMessage(_:)),
			keyEquivalent: ""
		)
		reply.target = target
		reply.command = .webReply
		reply.representedObject = context
		reply.image = NSImage(
			systemSymbolName: "arrowshape.turn.up.left",
			accessibilityDescription: reply.title
		)

		let react = NSMenuItem(title: MessageMenuStrings.react, action: nil, keyEquivalent: "")
		react.command = .webReact
		react.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: react.title)

		let reactMenu = NSMenu(title: react.title)

		for emoji in ["👍", "❤️", "😂", "😮", "😢", "👎"] {
			let item = NSMenuItem(
				title: emoji,
				action: #selector(TXMenuController.reactToMessage(_:)),
				keyEquivalent: ""
			)
			item.target = target
			item.command = .webReact
			item.representedObject = context.reacting(with: emoji)
			reactMenu.addItem(item)
		}

		reactMenu.addItem(.separator())

		let other = NSMenuItem(
			title: MessageMenuStrings.otherReaction,
			action: #selector(TXMenuController.reactToMessageWithOtherEmoji(_:)),
			keyEquivalent: ""
		)
		other.target = target
		other.command = .webReact
		other.representedObject = context
		reactMenu.addItem(other)
		react.submenu = reactMenu

		return [separator, reply, react]
	}

	public static func shareMenuItem(for items: [Any]) -> NSMenuItem {
		let title = MessageMenuStrings.share
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

	private static func apply(_ configuration: NSImage.SymbolConfiguration, to menu: NSMenu?) {
		guard let menu else {
			return
		}

		var hasSymbol = false

		for item in menu.items {
			if item.image == nil,
			   let symbolName = symbolName(forTag: item.tag),
			   let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title)
			{
				item.image = symbol
			}

			let currentImage = item.image

			if let symbolSpacer, currentImage === symbolSpacer {
				hasSymbol = true
			} else if let configuredImage = currentImage?.withSymbolConfiguration(configuration) {
				item.image = configuredImage
				hasSymbol = true
			}

			/* Every item that ends up carrying an image wants this, not just
			 the spacers added below; otherwise real symbols stay hidden while
			 the blank spacers next to them are shown. */
			if #available(macOS 27.0, *), item.image != nil {
				item.preferredImageVisibility = .visible
			}

			if item.hasSubmenu {
				apply(configuration, to: item.submenu)
			}
		}

		guard hasSymbol else {
			return
		}

		guard let symbolSpacer else {
			return
		}

		for item in menu.items where item.isSeparatorItem == false && item.image == nil {
			item.image = symbolSpacer

			if #available(macOS 27.0, *) {
				item.preferredImageVisibility = .visible
			}
		}
	}
}

/// The payload carried by the reply/react items of the channel view's context
/// menu. `NSMenuItem.representedObject` is `Any?`, so this stays a class the
/// action side can cast to in one step instead of a `[String: String]` unpacked
/// by literal key.
@MainActor
public final class MessageMenuContext {
	public let messageIdentifier: String
	public let nickname: String?
	public let excerpt: String?
	public let emoji: String?

	public init(
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
	public func reacting(with emoji: String) -> MessageMenuContext {
		MessageMenuContext(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt,
			emoji: emoji
		)
	}
}
