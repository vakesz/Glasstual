// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// The window's title and subtitle. What they say is
/// ``MainWindowTitleContent``'s; when they are said is this extension's.
extension MainWindow {
	func updateTitle(for item: ChatItem) {
		/* The topic bar carries a channel's modes as a caption, and the same
		 events that retitle the window are what change them. Nothing in the IRC
		 layer addresses one transcript when a mode lands, so the redraw rides
		 along here. */
		item.transcriptController?.refreshTopicBar()
		if isItemSelected(item) || (item.isSession && selectedSession === item) {
			updateTitle()
		}
	}

	func updateTitle() {
		let content = MainWindowTitleContent(session: selectedSession, conversation: selectedConversation)
		title = content.title
		subtitle = content.subtitle
		setAccessibilityTitle([content.title, content.subtitle].filter { $0.isEmpty == false }.joined(separator: ", "))
	}
}
