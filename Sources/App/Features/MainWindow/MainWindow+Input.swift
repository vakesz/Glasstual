// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

// MARK: - View controls and input

extension MainWindow {
	private enum TextZoomPolicy {
		static let step = 1.2
		static let allowedRange = 0.5 ... 3.0
	}

	func changeTextSize(_ bigger: Bool) {
		let next = bigger ? textSizeMultiplier * TextZoomPolicy.step : textSizeMultiplier / TextZoomPolicy.step
		guard TextZoomPolicy.allowedRange.contains(next) else { return }
		textSizeMultiplier = next
		for controller in transcriptControllersInDirectory {
			controller.changeTextSize(bigger)
		}
	}

	/// Actual Size: back to the unscaled text, in as many steps as it took to
	/// leave it. The controllers only know how to step, so the window walks
	/// them back rather than teaching them a second way to be told.
	func resetTextSize() {
		while textSizeMultiplier > 1.0 {
			let previous = textSizeMultiplier
			changeTextSize(false)
			if textSizeMultiplier == previous || textSizeMultiplier < 1.0 {
				break
			}
		}
		while textSizeMultiplier < 1.0 {
			let previous = textSizeMultiplier
			changeTextSize(true)
			if textSizeMultiplier == previous || textSizeMultiplier > 1.0 {
				break
			}
		}
		textSizeMultiplier = 1.0
	}

	private var transcriptControllersInDirectory: [TranscriptController] {
		guard let clientDirectory else { return [] }
		return clientDirectory.clientList.flatMap { client in
			[client.transcriptController].compactMap(\.self) + client.channelList.compactMap(\.transcriptController)
		}
	}

	func markAllAsRead() {
		guard let clientDirectory else { return }
		let markScrollback = Preferences.Messages.autoAddScrollbackMark.value
		for client in clientDirectory.clientList {
			if markScrollback {
				client.transcriptController?.mark()
			}
			for channel in client.channelList {
				if markScrollback {
					channel.transcriptController?.mark()
				}
				channel.resetState()
			}
		}
		DockIcon.updateDockIcon()
		reloadTree()
	}

	func reloadTheme() {
		for controller in transcriptControllersInDirectory {
			controller.reloadTheme()
		}
	}

	func clearContents(of client: Client) {
		client.resetState()
		client.transcriptController?.clear()
		reloadChatItem(client)
	}

	func clearContents(of channel: Channel) {
		channel.resetState()
		channel.transcriptController?.clear()
		reloadChatItem(channel)
	}

	private func completeNickname(_ movingForward: Bool) {
		nicknameCompletionStatus.completeNickname(movingForward)
	}

	/// Answers whether the window acted on Tab; `false` leaves the key to the
	/// message field's own keyboard navigation.
	func tab(_: NSEvent) -> Bool {
		performTabKeyAction(movingForward: true)
	}

	func shiftTab(_: NSEvent) -> Bool {
		performTabKeyAction(movingForward: false)
	}

	private func performTabKeyAction(movingForward: Bool) -> Bool {
		switch Preferences.Input.tabKeyAction.value {
		case .nicknameComplete:
			completeNickname(movingForward)
		case .unreadChannel:
			navigateChannelEntries(movingForward, withNavigationType: .unread)
		case .none:
			// The window declines the key, and the field moves the keyboard on.
			return false
		}
		return true
	}

	func sendControlEnterMessageMaybe(_ event: NSEvent) {
		if Preferences.Input.controlEnterSendsMessage.value {
			textEntered()
		} else {
			inputTextField.keyDownToSuper(event)
		}
	}

	func sendMessageAsAction(_: NSEvent) {
		if Preferences.Input.commandReturnSendsAction.value {
			inputTextAsCommand(.privmsgAction)
		} else {
			textEntered()
		}
	}

	private func moveInputHistory(_ movingUp: Bool, checkScroller: Bool, event: NSEvent) {
		if checkScroller {
			let caret = inputTextField.caretLocation
			if caret != .onlyLine {
				let atTop = caret == .firstLine
				let atBottom = caret == .lastLine
				if (atTop && event.keyCode == KeyCode.downArrow.rawValue) ||
					(atBottom && event.keyCode == KeyCode.upArrow.rawValue) ||
					(atTop == false && atBottom == false)
				{
					inputTextField.keyDownToSuper(event)
					return
				}
			}
		}
		let value = inputTextField.attributedStringValue
		guard let newValue = movingUp ? inputHistory.up(value) : inputHistory.down(value) else { return }
		inputTextField.attributedStringValue = newValue
		inputTextField.focus()
		if movingUp == false {
			inputTextField.setSelectedRange(NSRange(location: 0, length: 0))
		}
	}

	func inputHistoryUp(_ event: NSEvent) {
		moveInputHistory(true, checkScroller: false, event: event)
	}

	func inputHistoryDown(_ event: NSEvent) {
		moveInputHistory(false, checkScroller: false, event: event)
	}

	func inputHistoryUpWithScrollCheck(_ event: NSEvent) {
		moveInputHistory(
			true,
			checkScroller: true,
			event: event
		)
	}

	func inputHistoryDownWithScrollCheck(_ event: NSEvent) {
		moveInputHistory(
			false,
			checkScroller: true,
			event: event
		)
	}

	func textFormattingForegroundColor(_: NSEvent) {
		guard formattingMenu.isSet(.spoiler) == false else { return }
		if formattingMenu.isSet(.foregroundColorSet) {
			formattingMenu.setEffect(.foregroundColorSet, enabled: false)
			return
		}
		popUpColorMenu(formattingMenu.foregroundColorMenu)
	}

	func textFormattingBackgroundColor(_: NSEvent) {
		guard formattingMenu.isSet(.spoiler) == false, formattingMenu.isSet(.foregroundColorSet) else { return }
		if formattingMenu.isSet(.backgroundColorSet) {
			formattingMenu.setEffect(.backgroundColorSet, enabled: false)
			return
		}
		popUpColorMenu(formattingMenu.backgroundColorMenu)
	}

	/// The colour the menu picks applies at the caret, so the menu opens there
	/// — in the field's own coordinates, which is what `popUp` expects.
	private func popUpColorMenu(_ menu: NSMenu) {
		menu.popUp(positioning: nil, at: inputTextField.selectedRect.origin, in: inputTextField)
	}

	func focusTranscript(_: NSEvent) {
		guard attachedSheet == nil, let view = selectedViewController?.backingView else { return }
		makeFirstResponder(view)
	}

	func textEntered() {
		inputTextAsCommand(.privmsg)
	}

	private func inputTextAsCommand(_ command: RemoteCommand) {
		nicknameCompletionStatus.clear()
		/* NSTextView returns its live mutable text storage. Snapshot it before
		 clearing the editor, or the value handed to the client becomes empty too. */
		let value = NSAttributedString(attributedString: inputTextField.attributedStringValue)
		guard value.length > 0 else { return }
		inputTextField.attributedStringValue = NSAttributedString(string: "")
		inputHistory.add(value)
		inputTextField.consumeReply(into: selectedClient)
		inputText(value, asCommand: command)
	}

	func inputText(_ string: Any, asCommand command: RemoteCommand) {
		guard let destination = selectedItem, let client = destination.associatedClient else { return }
		client.inputText(string, as: command, destination: destination)
	}
}
