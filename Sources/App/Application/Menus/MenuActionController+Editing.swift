// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

// MARK: - Editing commands

extension MenuActionController {
	/** Runs Edit ▸ Find on the transcript's own find bar.

	 Searching a document belongs inline above the text, where every macOS
	 document window puts it: the modal prompt this replaced could not show how
	 many matches there were, could not step through them without being
	 reopened, and treated re-submitting the same phrase as no change at all,
	 so asking for the same word twice never advanced. ⌘G and ⇧⌘G keep their
	 meaning — they are the find bar's next and previous. */
	@objc func showFindPrompt(_ sender: NSMenuItem?) {
		guard let sender, mainWindow.isKeyWindow else {
			return
		}

		let action: NSTextFinder.Action = switch sender.command {
		case .findNext: .nextMatch
		case .findPrevious: .previousMatch
		case .useSelectionForFind: .setSearchString
		default: .showFindInterface
		}
		context.selectedBackingView?.performFindAction(action)
	}

	/** Paste goes wherever the keyboard is.

	 It used to focus the chat input whenever the main window was key, so pasting
	 while the caret sat in the toolbar's search field or a sheet's field pulled
	 the focus out of that field and dropped the text into the conversation. The
	 field is still the fallback the main window wants -- a paste with nothing
	 editable focused belongs in the message being written -- and
	 `MenuResponderCommandPolicy` is what decides between the two, so the action
	 and the menu item's validation answer the same question. */
	@objc func paste(_ sender: Any?) {
		let responder = NSApp.keyWindow?.firstResponder
		let inputTextField = mainWindow.isKeyWindow ? mainWindow.inputTextField : nil

		switch MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: (responder as? NSText)?.isEditable == true,
			responderIsInInputBar: context.responderBelongsToInputBar(responder),
			hasInputField: inputTextField != nil
		) {
		case .inputField:
			inputTextField?.focus()
			inputTextField?.paste(sender)
		case .firstResponder:
			forwardResponderAction(#selector(NSText.paste(_:)), sender: sender)
		case .none:
			break
		}
	}

	@objc func printTranscript(_ sender: Any?) {
		if mainWindow.isKeyWindow {
			context.selectedBackingView?.printContent()
			return
		}
		forwardResponderAction(#selector(NSView.printView(_:)), sender: sender)
	}

	private func forwardResponderAction(_ selector: Selector, sender: Any?) {
		guard let responder = NSApp.keyWindow?.firstResponder,
		      responder.responds(to: selector)
		else {
			return
		}
		_ = responder.perform(selector, with: sender)
	}
}
