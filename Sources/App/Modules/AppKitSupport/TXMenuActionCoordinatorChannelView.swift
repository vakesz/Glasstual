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
import CocoaExtensions

@MainActor
public extension MenuActionCoordinator {
	@objc(performChannelViewAction:sender:)
	func performChannelViewAction(_ action: TXMenuChannelViewAction, sender: Any?) {
		switch action {
		case .reply: reply(to: sender)
		case .react: react(to: sender)
		case .reactWithOtherEmoji: reactWithOtherEmoji(to: sender)
		case .copyLogAsHTML: objcSelectedViewControllerBackingView()?.copyContentString()
		case .openWebInspector: showWebInspectorUnavailableAlert()
		case .markScrollback: objcSelectedViewController()?.mark()
		case .goToScrollbackMarker: objcSelectedViewController()?.goToMark()
		case .clearScrollback: clearScrollback()
		case .increaseFontSize: mainWindow.changeTextSize(true)
		case .decreaseFontSize: mainWindow.changeTextSize(false)
		case .searchWeb: searchSelectedText()
		case .lookUpInDictionary: lookUpSelectedText()
		case .copyURL: copyURL(sender)
		@unknown default: break
		}
	}

	@objc(messageReplyItemsForMessageIdentifier:nickname:excerpt:)
	func messageReplyItems(messageIdentifier: String, nickname: String?, excerpt: String?) -> [NSMenuItem] {
		guard let menuController else { return [] }
		return MenuPresentation.messageReplyItems(
			messageIdentifier: messageIdentifier,
			nickname: nickname,
			excerpt: excerpt,
			target: menuController
		)
	}

	@objc(shareMenuItemForItems:)
	func shareMenuItem(for items: [Any]) -> NSMenuItem {
		MenuPresentation.shareMenuItem(for: items)
	}

	private func messageContext(from sender: Any?) -> [String: String]? {
		(sender as? NSMenuItem)?.representedObject as? [String: String]
	}

	private func reply(to sender: Any?) {
		guard let context = messageContext(from: sender),
		      let identifier = context["messageIdentifier"],
		      identifier.isEmpty == false
		else { return }
		mainWindow.inputTextField?.beginReply(
			toMessageIdentifier: identifier,
			nickname: context["nickname"],
			excerpt: context["excerpt"]
		)
	}

	private func react(to sender: Any?) {
		guard let context = messageContext(from: sender) else { return }
		sendReaction(context["emoji"], messageIdentifier: context["messageIdentifier"])
	}

	private func sendReaction(_ emoji: String?, messageIdentifier: String?) {
		guard let emoji, emoji.isEmpty == false,
		      let messageIdentifier, messageIdentifier.isEmpty == false,
		      let client = mainWindow.selectedClient,
		      let channel = mainWindow.selectedChannel
		else { return }
		client.sendReaction(emoji, toMessageIdentifier: messageIdentifier, in: channel)
	}

	private func reactWithOtherEmoji(to sender: Any?) {
		guard let identifier = messageContext(from: sender)?["messageIdentifier"],
		      identifier.isEmpty == false,
		      let anchorView = objcSelectedViewControllerBackingView()?.webView,
		      let window = anchorView.window
		else { return }

		let popover = ReactionPopoverController(messageIdentifier: identifier)
		popover.completionBlock = { [weak self] emoji, messageIdentifier in
			self?.sendReaction(emoji, messageIdentifier: messageIdentifier)
		}
		let mouseLocation = window.convertPoint(fromScreen: NSEvent.mouseLocation)
		let viewLocation = anchorView.convert(mouseLocation, from: nil)
		popover.present(relativeTo: NSRect(origin: viewLocation, size: NSSize(width: 1, height: 1)), of: anchorView)
		reactionPopover = popover
	}

	private func showWebInspectorUnavailableAlert() {
		_ = TDCAlert.alert(
			withMessage: PromptStrings.WebInspector.unavailableBody,
			title: PromptStrings.WebInspector.unavailableTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	private func clearScrollback() {
		guard let client = selectedClient else { return }
		if let channel = selectedChannel {
			mainWindow.clearContents(of: channel)
		} else {
			mainWindow.clearContents(of: client)
		}
	}

	private func searchSelectedText() {
		guard let selection = objcSelectedViewControllerBackingView()?.selection,
		      selection.isEmpty == false
		else { return }
		let pasteboard = NSPasteboard(name: NSPasteboard.Name("Glasstual.Search.\(UUID().uuidString)"))
		pasteboard.setString(selection, forType: .string)
		NSPerformService("Search With %WebSearchProvider@", pasteboard)
	}

	private func lookUpSelectedText() {
		guard let selection = objcSelectedViewControllerBackingView()?.selection,
		      selection.isEmpty == false,
		      let encodedSelection = selection.addingPercentEncoding(
		      	withAllowedCharacters: CharacterSet.textualPercentEncoded
		      )
		else { return }
		OpenLink.open(string: "dict://\(encodedSelection)")
	}

	private func copyURL(_ sender: Any?) {
		guard let url = (sender as? NSMenuItem)?.textualUserInfo, url.isEmpty == false else { return }
		NSPasteboard.general.setString(url, forType: .string)
	}
}
