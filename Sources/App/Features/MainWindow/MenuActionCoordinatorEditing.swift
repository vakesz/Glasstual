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
import CocoaExtensions

@MainActor
public extension MenuActionCoordinator {
	func performEditingAction(_ action: MenuEditingAction, sender: Any?) {
		switch action {
		case .showFindPrompt:
			showFindPrompt(sender)
		case .paste:
			paste(sender)
		case .print:
			printContent(sender)
		@unknown default:
			break
		}
	}

	/** Runs Edit ▸ Find on the transcript's own find bar.

	 Searching a document belongs inline above the text, where every macOS
	 document window puts it: the modal prompt this replaced could not show how
	 many matches there were, could not step through them without being
	 reopened, and treated re-submitting the same phrase as no change at all,
	 so asking for the same word twice never advanced. ⌘G and ⇧⌘G keep their
	 meaning — they are the find bar's next and previous. */
	private func showFindPrompt(_ sender: Any?) {
		guard sender != nil, mainWindow.isKeyWindow else {
			return
		}

		let action: NSTextFinder.Action = switch (sender as? NSMenuItem)?.command {
		case .findNext: .nextMatch
		case .findPrevious: .previousMatch
		case .useSelectionForFind: .setSearchString
		default: .showFindInterface
		}
		selectedBackingView?.performFindAction(action)
	}

	/** Paste goes wherever the keyboard is.

	 It used to focus the chat input whenever the main window was key, so pasting
	 while the caret sat in the toolbar's search field or a sheet's field pulled
	 the focus out of that field and dropped the text into the conversation. The
	 field is still the fallback the main window wants -- a paste with nothing
	 editable focused belongs in the message being written -- and
	 `MenuResponderCommandPolicy` is what decides between the two, so the action
	 and the menu item's validation answer the same question. */
	private func paste(_ sender: Any?) {
		let responder = NSApp.keyWindow?.firstResponder
		let inputTextField = mainWindow.isKeyWindow ? mainWindow.inputTextField : nil

		switch MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: (responder as? NSText)?.isEditable == true,
			responderIsInInputBar: responderBelongsToInputBar(responder),
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

	/// Whether the responder is the message field or anything else the input bar
	/// hosts, which is the one case where re-focusing the field changes nothing.
	/// Menu validation asks it too, so that the item and the action agree.
	func responderBelongsToInputBar(_ responder: NSResponder?) -> Bool {
		guard let inputBar = mainWindow.inputContentView, let view = responder as? NSView else {
			return false
		}
		return view.isDescendant(of: inputBar)
	}

	private func printContent(_ sender: Any?) {
		if mainWindow.isKeyWindow {
			selectedBackingView?.printContent()
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
