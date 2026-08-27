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
	private static let symbolNamesByTag: [Int: String] = [
		102: "gear", 113: "power", 200: "bell.slash", 201: "speaker.slash",
		203: "printer", 205: "xmark", 300: "arrow.uturn.backward", 301: "arrow.uturn.forward",
		303: "scissors", 304: "doc.on.doc", 305: "doc.on.clipboard", 306: "trash",
		307: "selection.pin.in.out", 400: "bookmark", 403: "envelope.open", 404: "eraser",
		406: "textformat.size.larger", 407: "textformat.size.smaller",
		409: "arrow.up.left.and.arrow.down.right", 500: "bolt", 501: "bolt.badge.clock",
		502: "bolt.slash", 503: "xmark.circle", 505: "list.bullet", 506: "pencil",
		508: "plus", 509: "plus.square.on.square", 510: "trash", 512: "plus.circle",
		514: "slider.horizontal.3", 600: "arrow.right.square", 601: "arrow.left.square",
		603: "plus.circle", 604: "trash", 606: "doc.text", 608: "text.quote",
		609: "slider.horizontal.3", 611: "hand.raised", 616: "gearshape",
		712: "arrow.down.to.line", 716: "magnifyingglass", 800: "minus", 801: "plus.rectangle",
		803: "person.2", 804: "sidebar.left", 812: "macwindow", 813: "person.crop.circle",
		814: "hand.raised", 815: "doc.text", 816: "exclamationmark.bubble",
		817: "arrow.up.arrow.down.circle", 900: "info.circle", 907: "questionmark.circle",
		912: "hand.wave", 1000: "arrow.right.square", 1100: "link", 1200: "pencil",
		1202: "magnifyingglass", 1203: "book", 1205: "doc.on.doc", 1206: "doc.on.clipboard",
		1208: "doc.text", 1209: "number", 1300: "plus", 1302: "plus.circle", 1400: "plus",
		1600: "hand.raised", 1601: "pencil", 1602: "hand.raised.slash", 1604: "envelope",
		1606: "info.circle", 1607: "bubble.left", 1619: "nosign", 1620: "figure.walk",
		1621: "nosign", 1623: "arrow.left.arrow.right", 1624: "shield", 1700: "bell.slash",
		1701: "speaker.slash", 1800: "xmark", 1802: "doc.text", 3_090_000: "magnifyingglass",
	]

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
		symbolNamesByTag[tag]
	}

	static var symbolMappings: [Int: String] {
		symbolNamesByTag
	}

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
			title: MessageMenuStrings.reply,
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

		let react = NSMenuItem(title: MessageMenuStrings.react, action: nil, keyEquivalent: "")
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
			title: MessageMenuStrings.otherReaction,
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
