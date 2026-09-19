// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** What the transcript can ask the rest of the window to do, and the menus it
 borrows from it.

 Joining a channel, opening a conversation, setting a topic, reacting and
 sending a dropped file are all the window's commands: the transcript is where
 the reader raises them, not where they are carried out. A struct of closures
 rather than a reference to the menu controller, so the transcript names the
 nine things it needs instead of reaching a process-wide singleton at nine
 scattered sites — and so a transcript can be built in a test with no
 application delegate at all.

 ``menuController()`` is the composition the application uses; the empty
 defaults are what a transcript with nowhere to send its commands does. */
@MainActor
struct TranscriptCommandSink {
	var joinChannel: (String) -> Void = { _ in }
	/// Opens a conversation with the nickname the reader double-clicked.
	var openConversation: (String) -> Void = { _ in }
	var modifyTopic: () -> Void = {}
	var react: (MessageMenuContext) -> Void = { _ in }
	var sendDroppedFiles: ([String]) -> Void = { _ in }
	/// The window's menu for a channel name, whose items the transcript copies.
	var channelNameMenu: () -> NSMenu? = { nil }
	/// The window's menu for a link.
	var linkMenu: () -> NSMenu? = { nil }
	/// The window's menu for a member, which the member list raises as well.
	var memberMenu: () -> NSMenu? = { nil }
	var messageReplyItems: (
		_ messageIdentifier: String,
		_ nickname: String?,
		_ excerpt: String?
	) -> [NSMenuItem] = { _, _, _ in [] }

	/** The menu controller the application delegate holds, or nothing before it
	 has one — which is every test that builds a transcript without an
	 application. The one place this feature names it. */
	private static var menuActionController: MenuActionController? {
		AppServices.delegate?.menuController
	}

	/// The sink the window composes: every command the transcript raises is one
	/// the menu controller already answers for the selected conversation.
	static func menuController() -> Self {
		Self(
			joinChannel: { menuActionController?.joinChannel(named: $0) },
			openConversation: { nickname in
				guard let controller = menuActionController else { return }
				controller.context.pointedNickname = nickname
				controller.memberInTranscriptDoubleClicked()
			},
			modifyTopic: { menuActionController?.showChannelModifyTopicSheet(nil) },
			react: { context in
				/* The command reads its context off the sender, which is how
				 every other caller of it raises it. */
				let sender = NSMenuItem()
				sender.representedObject = context
				menuActionController?.reactToMessage(sender)
			},
			sendDroppedFiles: { menuActionController?.sendDroppedFilesToSelectedConversation($0) },
			channelNameMenu: { menuActionController?.transcriptChannelNameMenu },
			linkMenu: { menuActionController?.transcriptURLMenu },
			memberMenu: { menuActionController?.userControlMenu },
			messageReplyItems: { identifier, nickname, excerpt in
				menuActionController?.messageReplyItems(
					messageIdentifier: identifier,
					nickname: nickname,
					excerpt: excerpt
				) ?? []
			}
		)
	}
}
