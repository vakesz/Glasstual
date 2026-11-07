// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/// Where the live application is asked about its conversations, and where a
/// match is shown. Kept apart from the model so the model needs neither.
@MainActor
enum ScrollbackSearchReveal {
	/// Selects the conversation a match belongs to and shows its line, loading
	/// the stored lines around it when they are not on screen.
	static func show(_ hit: ScrollbackSearchHit) async -> Bool {
		guard let item = AppServices.chatSession?.findItem(withId: hit.viewIdentifier),
		      let mainWindow = AppServices.delegate?.mainWindow
		else { return false }
		mainWindow.select(item)
		if mainWindow.isVisible == false {
			mainWindow.makeKeyAndOrderFront(nil)
		}
		guard let controller = item.transcriptController else { return false }
		return await controller.showHistoryWindow(around: hit)
	}
}

@MainActor
extension ScrollbackSearchTargets {
	/// Every conversation that keeps stored history, and the main window's
	/// selection. The server console and direct chats are left out: neither
	/// replays stored lines.
	static func current() -> Self {
		guard let chatSession = AppServices.chatSession else { return .empty }
		var targets = Self()
		for session in chatSession.sessions {
			for conversation in session.conversationList where conversation.isConsole == false
				&& conversation.isDirectChat == false
			{
				targets.entries.append(ScrollbackSearchTarget(
					viewIdentifier: conversation.uniqueIdentifier,
					title: conversation.name,
					serverIdentifier: session.uniqueIdentifier,
					serverName: session.networkNameAlt
				))
			}
		}
		let mainWindow = AppServices.delegate?.mainWindow
		targets.selectedViewIdentifier = mainWindow?.selectedConversation?.uniqueIdentifier
		targets.selectedServerIdentifier = mainWindow?.selectedSession?.uniqueIdentifier
		return targets
	}
}
