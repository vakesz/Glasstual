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

	private func showFindPrompt(_ sender: Any?) {
		guard sender != nil, mainWindow.isKeyWindow else {
			return
		}

		let command = (sender as? NSMenuItem)?.command
		if command == .findText || currentSearchPhrase.isEmpty {
			showFindPromptOpenDialog()
			return
		}

		selectedBackingView?.findString(
			currentSearchPhrase,
			movingForward: command == .findNext
		)
	}

	private func showFindPromptOpenDialog() {
		InputPrompt.present(InputPromptRequest(
			title: PromptStrings.TextSearch.title,
			message: PromptStrings.TextSearch.body,
			submitButtonTitle: PromptStrings.TextSearch.buttonTitle,
			cancelButtonTitle: PromptStrings.Action.cancel,
			initialValue: currentSearchPhrase
		)) { [weak self] outcome in
			guard let self,
			      case let .submitted(result) = outcome,
			      currentSearchPhrase != result
			else {
				return
			}
			currentSearchPhrase = result
			selectedBackingView?.findString(result, movingForward: true)
		}
	}

	private func paste(_ sender: Any?) {
		if mainWindow.isKeyWindow, let textField = mainWindow.inputTextField {
			textField.focus()
			textField.paste(sender)
			return
		}
		forwardResponderAction(#selector(NSText.paste(_:)), sender: sender)
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
