// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Transcript commands

extension MenuActionController {
	@objc func replyToMessage(_ sender: NSMenuItem?) {
		guard let message = messageContext(from: sender),
		      message.messageIdentifier.isEmpty == false
		else { return }
		mainWindow.inputTextField?.beginReply(
			toMessageIdentifier: message.messageIdentifier,
			nickname: message.nickname,
			excerpt: message.excerpt
		)
	}

	@objc func reactToMessage(_ sender: NSMenuItem?) {
		guard let message = messageContext(from: sender) else { return }
		sendReaction(message.emoji, messageIdentifier: message.messageIdentifier)
	}

	@objc func reactToMessageWithOtherEmoji(_ sender: NSMenuItem?) {
		guard let identifier = messageContext(from: sender)?.messageIdentifier,
		      identifier.isEmpty == false,
		      let transcript = context.selectedBackingView, transcript.window != nil
		else { return }

		/* The transcript presents and owns the picker: it is anchored to the
		 characters the message drew, which is knowledge only it has. */
		transcript.presentReactionPicker(forMessage: identifier) { [weak self] emoji in
			self?.sendReaction(emoji, messageIdentifier: identifier)
		}
	}

	@objc func setUnreadMarker(_: Any?) {
		context.selectedViewController?.mark()
	}

	@objc func gotoUnreadMarker(_: Any?) {
		context.selectedViewController?.goToMark()
	}

	@objc func clearScrollback(_: Any?) {
		guard let session = context.selectedSession else { return }
		if let conversation = context.selectedConversation {
			mainWindow.clearContents(of: conversation)
		} else {
			mainWindow.clearContents(of: session)
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
		guard let selection = context.selectedBackingView?.selection,
		      selection.isEmpty == false
		else { return }
		/* A pasteboard named by hand is never reclaimed: every search left one
		 behind in the pasteboard server for the life of the login session.
		 `withUniqueName()` hands back one this process owns, and releasing it
		 after the service has copied the text gives it back. */
		let pasteboard = NSPasteboard.withUniqueName()
		defer { pasteboard.releaseGlobally() }
		pasteboard.stringContent = selection
		NSPerformService("Search With %WebSearchProvider@", pasteboard)
	}

	@objc func lookUpInDictionary(_: Any?) {
		guard let selection = context.selectedBackingView?.selection, selection.isEmpty == false else { return }
		guard let encodedSelection = selection.addingPercentEncoding(
			withAllowedCharacters: CharacterSet.unreservedURICharacters
		) else { return }
		OpenLink.open(string: "dict://\(encodedSelection)")
	}

	@objc func copyURL(_ sender: NSMenuItem?) {
		guard let url = sender?.userInfoString, url.isEmpty == false else { return }
		NSPasteboard.general.stringContent = url
	}

	@objc func openLogLocation(_: Any?) {
		openLog(at: ApplicationPaths.transcriptFolderURL)
	}

	/// Channel ▸ View Logs and Query ▸ Query Logs are one command: it reveals
	/// whatever the selected conversation writes to.
	@objc func openConversationLogs(_: Any?) {
		openLog(at: context.selectedConversation?.logFilePath)
	}

	func messageReplyItems(messageIdentifier: String, nickname: String?, excerpt: String?) -> [NSMenuItem] {
		MenuPresentation.messageReplyItems(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt,
			target: self
		)
	}

	private func messageContext(from sender: NSMenuItem?) -> MessageMenuContext? {
		sender?.representedObject as? MessageMenuContext
	}

	/// Reveals a transcript file, or says why there is nothing to reveal.
	private func openLog(at url: URL?) {
		guard let url else { return }
		if FileManager.default.fileExists(atPath: url.path) {
			NSWorkspace.shared.open(url)
			return
		}
		Alerts.alert(
			title: PromptStrings.Logging.noLogsTitle,
			body: PromptStrings.Logging.emptyAlertBody,
			defaultButton: PromptStrings.Action.confirmation
		)
	}

	private func sendReaction(_ emoji: String?, messageIdentifier: String?) {
		guard let emoji, emoji.isEmpty == false,
		      let messageIdentifier, messageIdentifier.isEmpty == false,
		      let session = mainWindow.selectedSession,
		      let conversation = mainWindow.selectedConversation
		else { return }
		session.sendReaction(emoji, toMessageIdentifier: messageIdentifier, in: conversation)
	}
}
