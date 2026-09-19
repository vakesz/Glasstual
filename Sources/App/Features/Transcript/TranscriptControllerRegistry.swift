// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The window's transcript controllers, keyed by the identifier of the chat item each
 one draws.

 The controllers used to hang off the chat items themselves, which meant the IRC
 layer both built a transcript and owned it for the rest of its life. They belong
 to the window that shows them, so the window keeps them here and the chat item
 holds only a weak `presentation` back-reference the registry installs. */
@MainActor
final class TranscriptControllerRegistry {
	private unowned let window: MainWindow
	private var controllers: [String: TranscriptController] = [:]
	/// Built once per window and handed to every controller: the transcript
	/// raises the window's commands without naming where they live.
	private let commands = TranscriptCommandSink.menuController()

	init(window: MainWindow) {
		self.window = window
	}

	var count: Int {
		controllers.count
	}

	/** The controller drawing `session`, made on first use.

	 A chat item is a session or a conversation in one, so the two overloads are
	 every kind there is and the registry never has to guess which it was
	 handed. */
	@discardableResult
	func controller(for session: ServerSession) -> TranscriptController {
		controllers[session.uniqueIdentifier] ?? register(
			TranscriptController(session: session, in: window, commands: commands), for: session
		)
	}

	/// The controller drawing `conversation`, made on first use.
	@discardableResult
	func controller(for conversation: Conversation) -> TranscriptController {
		controllers[conversation.uniqueIdentifier] ?? register(
			TranscriptController(conversation: conversation, in: window, commands: commands), for: conversation
		)
	}

	private func register(_ controller: TranscriptController, for item: ChatItem) -> TranscriptController {
		controllers[item.uniqueIdentifier] = controller
		item.presentation = controller
		return controller
	}

	/// The controller drawing `item` if one has already been made.
	func existingController(for item: ChatItem) -> TranscriptController? {
		controllers[item.uniqueIdentifier]
	}

	func controller(withIdentifier identifier: String) -> TranscriptController? {
		controllers[identifier]
	}

	/// Makes the controllers for a session and every conversation it already has.
	func registerSidebar(of session: ServerSession) {
		controller(for: session)

		for conversation in session.conversationList {
			controller(for: conversation)
		}
	}

	/// Forgets the controller for `item`. The caller has already told the
	/// controller to tear itself down.
	func forget(_ item: ChatItem) {
		if item.presentation === controllers[item.uniqueIdentifier] {
			item.presentation = nil
		}

		controllers.removeValue(forKey: item.uniqueIdentifier)
	}

	/// Forgets a session and every conversation it has.
	func forgetSidebar(of session: ServerSession) {
		for conversation in session.conversationList {
			forget(conversation)
		}

		forget(session)
	}
}

extension ChatItem {
	/** The view this item is drawn into, if a window has made one.

	 This reads the weak seam the registry installed rather than a property the
	 item owns, so it is `nil` for an item no window is showing — a session in a
	 test, or one whose registry entry has already been dropped. */
	var transcriptController: TranscriptController? {
		presentation as? TranscriptController
	}
}
