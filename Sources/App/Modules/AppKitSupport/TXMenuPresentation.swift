/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
@objc(TXMenuPresentation)
public final class MenuPresentation: NSObject {
	private static let symbolConfiguration = NSImage.SymbolConfiguration(
		pointSize: NSFont.systemFontSize,
		weight: .regular,
		scale: .medium
	)

	/// One stable instance lets repeated passes distinguish padding from a
	/// real symbol. A transparent bitmap is treated as no image on macOS 26.
	private static let symbolSpacer: NSImage = {
		let configuration = symbolConfiguration.applying(
			NSImage.SymbolConfiguration(paletteColors: [.clear])
		)
		let image = NSImage(
			systemSymbolName: "circle",
			accessibilityDescription: nil
		)?.withSymbolConfiguration(configuration)

		precondition(image != nil, "The system circle symbol must be available")

		image?.isTemplate = false

		return image!
	}()

	@objc(applyToMenu:)
	public static func apply(to menu: NSMenu?) {
		apply(symbolConfiguration, to: menu)
	}

	@objc(messageReplyItemsForMessageIdentifier:nickname:excerpt:target:)
	public static func messageReplyItems(
		messageIdentifier: String,
		nickname: String?,
		excerpt: String?,
		target: AnyObject
	) -> [NSMenuItem] {
		var context = ["messageIdentifier": messageIdentifier]

		context["nickname"] = nickname
		context["excerpt"] = excerpt

		let separator = NSMenuItem.separator()
		separator.tag = 1210

		let reply = NSMenuItem(
			title: LocalizedKey("TXMenuController[rpl-to]"),
			action: #selector(TXMenuController.replyToMessage(_:)),
			keyEquivalent: ""
		)
		reply.target = target
		reply.tag = 1211
		reply.representedObject = context
		reply.image = NSImage(
			systemSymbolName: "arrowshape.turn.up.left",
			accessibilityDescription: reply.title
		)

		let react = NSMenuItem(title: LocalizedKey("TXMenuController[rct-to]"), action: nil, keyEquivalent: "")
		react.tag = 1212
		react.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: react.title)

		let reactMenu = NSMenu(title: react.title)

		for emoji in ["👍", "❤️", "😂", "😮", "😢", "👎"] {
			let item = NSMenuItem(
				title: emoji,
				action: #selector(TXMenuController.reactToMessage(_:)),
				keyEquivalent: ""
			)
			item.target = target
			item.tag = 1212
			item.representedObject = context.merging(["emoji": emoji]) { _, replacement in replacement }
			reactMenu.addItem(item)
		}

		reactMenu.addItem(.separator())

		let other = NSMenuItem(
			title: LocalizedKey("TXMenuController[rct-ot]"),
			action: #selector(TXMenuController.reactToMessageWithOtherEmoji(_:)),
			keyEquivalent: ""
		)
		other.target = target
		other.tag = 1212
		other.representedObject = context
		reactMenu.addItem(other)
		react.submenu = reactMenu

		return [separator, reply, react]
	}

	@objc(shareMenuItemForItems:)
	public static func shareMenuItem(for items: [Any]) -> NSMenuItem {
		let title = LocalizedKey("TXMenuController[shr-m1]")
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
			let currentImage = item.image

			if currentImage === symbolSpacer {
				hasSymbol = true
			} else if let symbolName = currentImage?.name(), symbolName.isEmpty == false,
			          let symbol = NSImage(
			          	systemSymbolName: symbolName,
			          	accessibilityDescription: item.title
			          )?.withSymbolConfiguration(configuration)
			{
				item.image = symbol
				hasSymbol = true
			}

			if item.hasSubmenu {
				apply(configuration, to: item.submenu)
			}
		}

		guard hasSymbol else {
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
