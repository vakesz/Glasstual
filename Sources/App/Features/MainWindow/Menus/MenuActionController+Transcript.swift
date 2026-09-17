// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Transcript commands

extension MenuActionController {
	@objc func replyToMessage(_ sender: Any?) {
		guard let context = messageContext(from: sender),
		      context.messageIdentifier.isEmpty == false
		else { return }
		mainWindow.inputTextField?.beginReply(
			toMessageIdentifier: context.messageIdentifier,
			nickname: context.nickname,
			excerpt: context.excerpt
		)
	}

	@objc func reactToMessage(_ sender: Any?) {
		guard let context = messageContext(from: sender) else { return }
		sendReaction(context.emoji, messageIdentifier: context.messageIdentifier)
	}

	@objc func reactToMessageWithOtherEmoji(_ sender: Any?) {
		guard let identifier = messageContext(from: sender)?.messageIdentifier,
		      identifier.isEmpty == false,
		      let anchorView = selectedBackingView,
		      let window = anchorView.window
		else { return }

		let popover = ReactionPopover(messageIdentifier: identifier)
		popover.completion = { [weak self] emoji, messageIdentifier in
			self?.sendReaction(emoji, messageIdentifier: messageIdentifier)
		}
		let mouseLocation = window.convertPoint(fromScreen: NSEvent.mouseLocation)
		let viewLocation = anchorView.convert(mouseLocation, from: nil)
		popover.present(relativeTo: NSRect(origin: viewLocation, size: NSSize(width: 1, height: 1)), of: anchorView)
		reactionPopover = popover
	}

	@objc func markScrollback(_: Any?) {
		selectedViewController?.mark()
	}

	@objc func gotoScrollbackMarker(_: Any?) {
		selectedViewController?.goToMark()
	}

	@objc func clearScrollback(_: Any?) {
		guard let client = selectedClient else { return }
		if let channel = selectedChannel {
			mainWindow.clearContents(of: channel)
		} else {
			mainWindow.clearContents(of: client)
		}
	}

	@objc func increaseLogFontSize(_: Any?) {
		mainWindow.changeTextSize(true)
	}

	@objc func decreaseLogFontSize(_: Any?) {
		mainWindow.changeTextSize(false)
	}

	@objc func resetLogFontSize(_: Any?) {
		mainWindow.resetTextSize()
	}

	@objc func searchWeb(_: Any?) {
		guard let selection = selectedBackingView?.selection,
		      selection.isEmpty == false
		else { return }
		/* A pasteboard named by hand is never reclaimed: every search left one
		 behind in the pasteboard server for the life of the login session.
		 `withUniqueName()` hands back one this process owns, and releasing it
		 after the service has copied the text gives it back. */
		let pasteboard = NSPasteboard.withUniqueName()
		defer { pasteboard.releaseGlobally() }
		pasteboard.textualStringContent = selection
		NSPerformService("Search With %WebSearchProvider@", pasteboard)
	}

	@objc func lookUpInDictionary(_: Any?) {
		guard let selection = selectedBackingView?.selection,
		      selection.isEmpty == false,
		      let encodedSelection = selection.addingPercentEncoding(
		      	withAllowedCharacters: CharacterSet.textualPercentEncoded
		      )
		else { return }
		OpenLink.open(string: "dict://\(encodedSelection)")
	}

	@objc func copyURL(_ sender: Any?) {
		guard let url = (sender as? NSMenuItem)?.userInfoString, url.isEmpty == false else { return }
		NSPasteboard.general.setString(url, forType: .string)
	}

	func messageReplyItems(messageIdentifier: String, nickname: String?, excerpt: String?) -> [NSMenuItem] {
		MenuPresentation.messageReplyItems(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt,
			target: self
		)
	}

	private func messageContext(from sender: Any?) -> MessageMenuContext? {
		(sender as? NSMenuItem)?.representedObject as? MessageMenuContext
	}

	private func sendReaction(_ emoji: String?, messageIdentifier: String?) {
		guard let emoji, emoji.isEmpty == false,
		      let messageIdentifier, messageIdentifier.isEmpty == false,
		      let client = mainWindow.selectedClient,
		      let channel = mainWindow.selectedChannel
		else { return }
		client.sendReaction(emoji, toMessageIdentifier: messageIdentifier, in: channel)
	}
}
