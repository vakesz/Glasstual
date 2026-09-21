// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** What a menu command acts on.

 A command asks this and nothing else: the row a contextual menu was opened on
 when there is one, the main window's selection when there is not, and -- for
 Paste -- what holds the keyboard. Keeping the question here is what lets the
 command and its menu item answer it the same way, because validation asks the
 same object the action does.

 It also keeps the menu session: a menu opened over a row freezes what that row
 was until the command chosen from it has run. */
@MainActor
final class MenuContextResolver {
	/** What an explicitly clicked row means while a contextual menu validates
	 and runs its commands.

	 Without one, the main window's own selection answers — which is what a
	 menu bar command wants, and what a context menu opened on an unselected
	 row does not: it would validate against the row the person did not
	 click. */
	enum MenuContext {
		/// A server-list row. A nil item is the list's background: the server,
		/// or empty space, rather than the window's selected conversation.
		case sidebarItem(ChatItem?)
		/// Member-list rows, in the order the list shows them.
		case members([Member])
	}

	/// The connection, the conversation and the nicknames one member command
	/// applies to, resolved together because no such command needs less.
	struct MemberCommandTarget {
		let session: ServerSession
		let conversation: Conversation
		let nicknames: [String]
	}

	weak var pointedSession: ServerSession?
	weak var pointedConversation: Conversation?
	/// The nickname the transcript recorded for the row a menu was opened on.
	var pointedNickname: String?

	private var menuContext: MenuContext?
	var hasExplicitMenuContext: Bool {
		menuContext != nil
	}

	private var menuIsOpen = false
	private var menuPerformedActionLastOpen = false
	/// The deferred selection reset a closing menu schedules, held so that
	/// termination can cancel one that has not run yet.
	private var selectionResetTask: Task<Void, Never>?
	/// Menu-action and selection notifications, cancelled at termination.
	private let notifications = NotificationSubscriptions()
	/// The object the menu items send their actions to, so that another
	/// target's menu does not end a session this one is keeping.
	private weak var menuTarget: NSObject?

	var mainWindow: MainWindow {
		AppServices.delegate.mainWindow
	}

	var selectedSession: ServerSession? {
		if case let .sidebarItem(item) = menuContext {
			/* A member-list menu names members, not a connection, so it keeps
			 the window's selection: the members belong to it. */
			return (item as? ServerSession) ?? item?.associatedSession
		}
		return pointedSession ?? mainWindow.selectedSession
	}

	var selectedConversation: Conversation? {
		if case let .sidebarItem(item) = menuContext {
			return item as? Conversation
		}
		return pointedConversation ?? mainWindow.selectedConversation
	}

	/// The transcript the selection is showing, and the view drawing it.
	var selectedViewController: TranscriptController? {
		selectedConversation?.transcriptController ?? selectedSession?.transcriptController
	}

	var selectedBackingView: TranscriptView? {
		selectedViewController?.backingView
	}

	/// Whether the selected channel is known to carry `symbol`. The commands that
	/// set a mode and the items that tick it ask the same question. Only a
	/// `#channel` carries modes, so the callers guard on that first.
	func channelModeIsSet(_ symbol: String) -> Bool {
		selectedConversation?.modeInfo?.modeInfo(for: symbol)?.modeIsSet == true
	}

	/// Runs `perform` against the row a contextual menu was opened on, so that
	/// validation and execution both answer for what was clicked. Never
	/// publishes window selection while validating.
	func withContext<Result>(_ context: MenuContext, perform: () throws -> Result) rethrows -> Result {
		let previous = menuContext
		menuContext = context
		defer { menuContext = previous }
		return try perform()
	}

	// MARK: - Members

	/// Local presentation settings also apply to nicknames in old transcripts,
	/// after a sender has left or the connection has closed.
	func muteTarget(for sender: NSMenuItem?) -> (session: ServerSession, nickname: String)? {
		guard let session = selectedSession, selectedConversation?.isConsole == false else { return nil }
		let nickname: String?
		if let senderNickname = sender?.userInfoString {
			nickname = senderNickname
		} else if sender == nil, let pointedNickname {
			nickname = pointedNickname
		} else {
			let nicknames = selectedNicknames(for: sender)
			nickname = nicknames.count == 1 ? nicknames.first : nil
		}
		guard let nickname, nickname.isHostmaskNickname(on: session), !session.nicknameIsMyself(nickname) else { return nil }
		return (session, nickname)
	}

	/// The members a member-list command applies to: the one the menu was
	/// opened on, or the current selection.
	///
	/// This used to be one `-> [Any]` switched on a `returnNicknames` flag,
	/// with every caller casting the result back.
	func selectedMembers(for sender: NSMenuItem?) -> [Member] {
		guard let nickname = targetedNickname(for: sender) else {
			return selectedMemberListMembers()
		}

		guard let conversation = selectedConversation else {
			return []
		}

		return conversation.findMember(nickname).map { [$0] } ?? []
	}

	func selectedNicknames(for sender: NSMenuItem?) -> [String] {
		guard let nickname = targetedNickname(for: sender) else {
			return selectedMemberListMembers().map(\.user.nickname)
		}

		return [nickname]
	}

	/// What a member command was aimed at, whatever state the connection is in:
	/// each command adds the state it needs of the two to its own guard.
	///
	/// Resolving a target never clears the selection it read, because a command
	/// clears that only once it has acted — see ``deselectMembers(for:)``.
	func commandTarget(for sender: NSMenuItem?) -> MemberCommandTarget? {
		guard let session = selectedSession, let conversation = selectedConversation else {
			return nil
		}
		return MemberCommandTarget(
			session: session,
			conversation: conversation,
			nicknames: selectedNicknames(for: sender)
		)
	}

	func deselectMembers(for sender: NSMenuItem?) {
		if sender?.userInfoString?.isEmpty == false {
			return
		}
		if pointedNickname != nil {
			pointedNickname = nil
			return
		}
		mainWindow.memberList.deselectAll()
	}

	/// The nickname the command was aimed at, if it was aimed at one: either
	/// the menu item's own, or the one the transcript recorded. `nil` means "use
	/// the member list's selection".
	private func targetedNickname(for sender: NSMenuItem?) -> String? {
		guard hasLiveConversation else {
			return nil
		}

		/* A menu item answers for itself, even when it carries no nickname: the
		 transcript's recorded one belongs to a command that came from the
		 transcript, not to one sent from a menu. */
		if let sender {
			return sender.userInfoString
		}

		return pointedNickname
	}

	private func selectedMemberListMembers() -> [Member] {
		guard hasLiveConversation else {
			return []
		}

		/* The rows the menu was opened on, which are not the list's selection
		 until the command that follows replaces it. */
		if case let .members(members) = menuContext {
			return members
		}

		return mainWindow.memberList.selectedMembers
	}

	/// Whether the selection can carry a member command at all: a registered
	/// connection showing a conversation whose members are present.
	private var hasLiveConversation: Bool {
		guard let session = selectedSession, let conversation = selectedConversation else {
			return false
		}
		return session.isLoggedIn && conversation.isActive
	}

	// MARK: - The keyboard

	/// Whether the responder is the message field or anything else the input bar
	/// hosts, which is the one case where re-focusing the field changes nothing.
	/// Menu validation asks it too, so that the item and the action agree.
	func responderBelongsToInputBar(_ responder: NSResponder?) -> Bool {
		guard let inputBar = mainWindow.inputContentView, let view = responder as? NSView else {
			return false
		}
		return view.isDescendant(of: inputBar)
	}

	// MARK: - The menu session

	/** Watches the menus `target` owns for the length of one session.

	 A session is what freezes the clicked row: it opens when the reader opens a
	 root menu and closes once the command they chose has run. */
	func observeMenuSessions(sentBy target: NSObject) {
		menuTarget = target
		notifications.observe(NSMenu.willSendActionNotification) { [weak self] notification in
			guard let self, isOwnAction(notification) else { return }
			menuPerformedActionLastOpen = true
		}
		notifications.observe(NSMenu.didSendActionNotification) { [weak self] notification in
			guard let self, isOwnAction(notification) else { return }
			resetPointedItems()
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] _ in
			guard let self, menuIsOpen == false else { return }
			resetPointedItems()
		}
	}

	/** Only the menu the reader opened opens and closes a menu session.

	 Every submenu shares the delegate, and AppKit sends `menuWillOpen` and
	 `menuDidClose` for each of them as the pointer moves in and out. Treating a
	 submenu transition as a session boundary re-read the window's selection
	 half way through the menu -- so a command chosen from a submenu of a
	 right-clicked row acted on the row that was selected, not the one clicked
	 -- and closed the session while the root menu was still up. A root menu has
	 no supermenu; a submenu does. */
	func beginMenuSession(for menu: NSMenu) {
		guard menu.supermenu == nil else { return }
		menuIsOpen = true
		pointedSession = mainWindow.selectedSession
		pointedConversation = mainWindow.selectedConversation
		menuPerformedActionLastOpen = false
	}

	func endMenuSession(for menu: NSMenu) {
		guard menu.supermenu == nil else { return }
		menuIsOpen = false

		/* AppKit closes the menu before it sends the selected item's action.
		 Deferring to the next main-actor turn preserves the click-time
		 selection until that action has run. */
		selectionResetTask?.cancel()
		selectionResetTask = Task { [weak self] in
			guard let self, Task.isCancelled == false else {
				return
			}

			if menuPerformedActionLastOpen == false {
				resetPointedItems()
			}
		}
	}

	private func resetPointedItems() {
		pointedSession = nil
		pointedConversation = nil
	}

	func prepareForApplicationTermination() {
		selectionResetTask?.cancel()
		selectionResetTask = nil
		notifications.cancelAll()
	}

	private func isOwnAction(_ notification: Notification) -> Bool {
		(notification.userInfo?["MenuItem"] as? NSMenuItem)?.target === menuTarget
	}
}
