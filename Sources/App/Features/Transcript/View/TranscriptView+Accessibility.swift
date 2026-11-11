// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** What an assistive reader can do with the name under the text cursor.

 A pointer joins a channel or opens a nickname with a double click, and a
 keyboard reader reaches both through the context menu. A screen reader that
 only moves the cursor through the text finds neither, because the runs are
 not links: the text view offers each as a custom action while the selection
 sits on one, and the action does what the double click does. */
extension TranscriptView {
	/// The actions the selection or the caret offers, none while it sits on
	/// plain text.
	func nameAccessibilityActions() -> [NSAccessibilityCustomAction] {
		let target = selectedContextTarget()
		var actions: [NSAccessibilityCustomAction] = []
		if let channelName = target.channelName {
			actions.append(NSAccessibilityCustomAction(
				name: String(localized: .Transcript.joinChannelAction(channelName))
			) { [weak self] in
				guard let self else { return false }
				contextMenuTarget = target
				commands.channelNameDoubleClicked(in: self)
				return true
			})
		}
		if let nickname = target.nickname, nickname.isEmpty == false {
			actions.append(NSAccessibilityCustomAction(
				name: Self.nicknameActionTitle(for: nickname)
			) { [weak self] in
				guard let self else { return false }
				contextMenuTarget = target
				commands.nicknameDoubleClicked(in: self)
				return true
			})
		}
		return actions
	}

	/// Named for what the reader's double-click action will do with the name,
	/// since that is what performing it runs.
	private static func nicknameActionTitle(for nickname: String) -> String {
		switch SettingsKeys.Input.userDoubleClickAction.value {
		case .whois: String(localized: .Transcript.whoisNicknameAction(nickname))
		case .startDirectConversation: String(localized: .Transcript.openConversationNicknameAction(nickname))
		case .insertTextField: String(localized: .Transcript.insertNicknameAction(nickname))
		@unknown default: String(localized: .Transcript.openConversationNicknameAction(nickname))
		}
	}
}
