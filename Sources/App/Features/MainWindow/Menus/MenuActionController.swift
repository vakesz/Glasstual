// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

enum MenuMemberCommand {
	static func ignore(_ nickname: String) -> String {
		"ignore \(nickname)"
	}

	static func unignore(_ nickname: String) -> String {
		"unignore \(nickname)"
	}

	static func mode(_ command: String, nicknames: [String]) -> String {
		"\(command) \(nicknames.joined(separator: " "))"
	}

	static func kickban(_ nickname: String, reason: String) -> String {
		"KICKBAN \(nickname) \(reason)"
	}

	static func operatorCommand(_ command: String, nickname: String, reason: String) -> String {
		"\(command) \(nickname) \(reason)"
	}

	static func setVhost(_ vhost: String, nickname: String) -> String {
		"hs setall \(nickname) \(vhost)"
	}
}

/// One of the main window's navigation commands.
enum MenuNavigationAction: Sendable, CaseIterable {
	case nextServer
	case previousServer
	case nextActiveServer
	case previousActiveServer
	case nextChannel
	case previousChannel
	case nextActiveChannel
	case previousActiveChannel
	case nextUnreadChannel
	case previousUnreadChannel
	case moveBackward
	case moveForward
	case previousSelection
}

/** The menus the application shows, and every command they issue.

 The menu items target this object, so a command is the `@objc` method the item
 sends and nothing else: no forwarder stands in front of it. A command is still
 named twice -- once as a `MenuCommand` case that carries its title, key,
 symbol and validation group, and once as the selector the item sends -- and
 ``validateMenuItem(_:)`` switches on the first to decide the second's
 availability. */
@MainActor
final class MenuActionController: NSObject, NSMenuDelegate, NSMenuItemValidation {
	// MARK: - The menus themselves

	/* AppKit pops these up, and `MenuFactory` fills them. They sit on the same
	 object the items target, so a command is one `@objc` method: there is no
	 forwarder, no enum case naming it a second time, and no switch taking the
	 two apart again. */
	var transcriptChannelNameMenu = NSMenu()
	var transcriptGeneralMenu = NSMenu()
	var transcriptURLMenu = NSMenu()
	var dockMenu = NSMenu()
	var mainMenuNavigationChannelListMenu = NSMenu()
	var mainMenuChannelMenu = NSMenu()
	var mainMenuQueryMenu = NSMenu()
	var mainMenuChannelMenuItem: NSMenuItem?
	var mainMenuQueryMenuItem: NSMenuItem?
	var mainMenuServerMenuItem: NSMenuItem?
	var mainMenuFormatMenuItem: NSMenuItem?
	var serverListNoSelectionMenu = NSMenu()
	var userControlMenu = NSMenu()
	var muteNotificationsDockMenuItem: NSMenuItem?
	var muteNotificationsFileMenuItem: NSMenuItem?
	var muteNotificationsSoundsDockMenuItem: NSMenuItem?
	var muteNotificationsSoundsFileMenuItem: NSMenuItem?

	var menuIsOpen = false
	var menuPerformedActionLastOpen = false
	weak var pointedClient: Client?
	weak var pointedChannel: Channel?
	/// The nickname the transcript recorded for the row a menu was opened on.
	var pointedNickname: String?
	/** What an explicitly clicked row means while a contextual menu validates
	 and runs its commands.

	 Without one, the main window's own selection answers — which is what a
	 menu bar command wants, and what a context menu opened on an unselected
	 row does not: it would validate against the row the person did not
	 click. */
	enum MenuContext {
		/// A server-list row. A nil item is the list's background: the server,
		/// or empty space, rather than the window's selected channel.
		case treeItem(ChatItem?)
		/// Member-list rows, in the order the list shows them.
		case members([ChannelUser])
	}

	private var menuContext: MenuContext?
	var hasExplicitMenuContext: Bool {
		menuContext != nil
	}

	var reactionPopover: ReactionPopover?
	/// Menu-action and selection notifications, cancelled at termination.
	let notifications = NotificationSubscriptions()
	/// The deferred selection reset a closing menu schedules, held so that
	/// termination can cancel one that has not run yet.
	var selectionResetTask: Task<Void, Never>?
	var serverDuplicationTasks: [UUID: Task<Void, Never>] = [:]

	override init() {
		super.init()
		MenuFactory.install(on: self)
	}

	var mainWindow: MainWindow {
		AppServices.delegate.mainWindow
	}

	var selectedClient: Client? {
		if case let .treeItem(item) = menuContext {
			/* A member-list menu names members, not a connection, so it keeps
			 the window's selection: the members belong to it. */
			return (item as? Client) ?? item?.associatedClient
		}
		return pointedClient ?? mainWindow.selectedClient
	}

	var selectedChannel: Channel? {
		if case let .treeItem(item) = menuContext {
			return item as? Channel
		}
		return pointedChannel ?? mainWindow.selectedChannel
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

	/// The transcript the selection is showing, and the view drawing it.
	var selectedViewController: TranscriptController? {
		selectedChannel?.transcriptController ?? selectedClient?.transcriptController
	}

	var selectedBackingView: TranscriptView? {
		selectedViewController?.backingView
	}

	var fileTransferCenter: FileTransferCenter {
		AppServices.fileTransfers
	}

	/// The members a member-list command applies to: the one the menu was
	/// opened on, or the current selection.
	///
	/// This used to be one `-> [Any]` switched on a `returnNicknames` flag,
	/// with every caller casting the result back.
	func selectedMembers(for sender: Any) -> [ChannelUser] {
		guard let nickname = targetedNickname(for: sender) else {
			return selectedMemberListMembers()
		}

		guard let channel = selectedChannel else {
			return []
		}

		return channel.findMember(nickname).map { [$0] } ?? []
	}

	func selectedNicknames(for sender: Any) -> [String] {
		guard let nickname = targetedNickname(for: sender) else {
			return selectedMemberListMembers().map(\.user.nickname)
		}

		return [nickname]
	}

	/// The nickname the command was aimed at, if it was aimed at one: either
	/// the menu item's own, or the one the log view recorded. `nil` means "use
	/// the member list's selection".
	private func targetedNickname(for sender: Any) -> String? {
		guard let client = selectedClient,
		      let channel = selectedChannel,
		      client.isLoggedIn,
		      channel.isActive
		else {
			return nil
		}

		if let menuItem = sender as? NSMenuItem {
			return menuItem.userInfoString
		}

		return pointedNickname
	}

	/// The connections the menu acts on. They are set once the application has finished
	/// launching, which is before any menu command can run.
	var clientDirectory: ClientDirectory? {
		AppServices.clientDirectory
	}

	private func selectedMemberListMembers() -> [ChannelUser] {
		guard let client = selectedClient,
		      let channel = selectedChannel,
		      client.isLoggedIn,
		      channel.isActive
		else {
			return []
		}

		/* The rows the menu was opened on, which are not the list's selection
		 until the command that follows replaces it. */
		if case let .members(members) = menuContext {
			return members
		}

		return mainWindow.memberList.selectedMembers
	}

	func deselectMembers(for sender: Any) {
		if let menuItem = sender as? NSMenuItem,
		   menuItem.userInfoString?.isEmpty == false
		{
			return
		}
		if pointedNickname != nil {
			pointedNickname = nil
			return
		}
		mainWindow.memberList.deselectAll(sender)
	}
}

// MARK: - Member commands

extension MenuActionController {
	@objc func memberAddIgnore(_ sender: Any?) {
		performIgnore(sender: sender ?? NSNull(), remove: false)
	}

	@objc func memberRemoveIgnore(_ sender: Any?) {
		performIgnore(sender: sender ?? NSNull(), remove: true)
	}

	@objc func memberModifyIgnore(_ sender: Any?) {
		modifyIgnore(sender: sender ?? NSNull())
	}

	@objc func memberSendWhois(_ sender: Any?) {
		performForNicknames(sender: sender ?? NSNull()) { $0.sendWhois($1) }
	}

	@objc func memberStartPrivateMessage(_ sender: Any?) {
		startPrivateMessages(sender: sender ?? NSNull())
	}

	@objc func memberChangeColor(_ sender: Any?) {
		guard selectedClient != nil, selectedChannel != nil,
		      let nickname = selectedNicknames(for: sender ?? NSNull()).first
		else { return }

		showNicknameColorSheet(for: nickname)
	}

	@objc func memberSendCTCPPing(_ sender: Any?) {
		performForNicknames(sender: sender ?? NSNull()) { $0.sendCTCPPing($1) }
	}

	@objc func memberSendCTCPFinger(_ sender: Any?) {
		performCTCP("FINGER", sender: sender ?? NSNull())
	}

	@objc func memberSendCTCPTime(_ sender: Any?) {
		performCTCP("TIME", sender: sender ?? NSNull())
	}

	@objc func memberSendCTCPVersion(_ sender: Any?) {
		performCTCP("VERSION", sender: sender ?? NSNull())
	}

	@objc func memberSendCTCPUserinfo(_ sender: Any?) {
		performCTCP("USERINFO", sender: sender ?? NSNull())
	}

	@objc func memberSendCTCPClientInfo(_ sender: Any?) {
		performCTCP("CLIENTINFO", sender: sender ?? NSNull())
	}

	@objc func memberModeGiveOp(_ sender: Any?) {
		performMode("OP", sender: sender ?? NSNull())
	}

	@objc func memberModeTakeOp(_ sender: Any?) {
		performMode("DEOP", sender: sender ?? NSNull())
	}

	@objc func memberModeGiveHalfop(_ sender: Any?) {
		performMode("HALFOP", sender: sender ?? NSNull())
	}

	@objc func memberModeTakeHalfop(_ sender: Any?) {
		performMode("DEHALFOP", sender: sender ?? NSNull())
	}

	@objc func memberModeGiveVoice(_ sender: Any?) {
		performMode("VOICE", sender: sender ?? NSNull())
	}

	@objc func memberModeTakeVoice(_ sender: Any?) {
		performMode("DEVOICE", sender: sender ?? NSNull())
	}

	@objc func memberKickFromChannel(_ sender: Any?) {
		performChannelModeration(sender: sender ?? NSNull()) { client, channel, nickname in
			client.kick(nickname, in: channel)
		}
	}

	@objc func memberBanFromChannel(_ sender: Any?) {
		performChannelModeration(sender: sender ?? NSNull()) { client, channel, nickname in
			client.sendCommand("BAN \(nickname)", completeTarget: true, target: channel.name)
		}
	}

	@objc func memberKickbanFromChannel(_ sender: Any?) {
		performChannelModeration(sender: sender ?? NSNull()) { client, channel, nickname in
			client.sendCommand(
				MenuMemberCommand.kickban(nickname, reason: Preferences.Commands.kickMessage.value),
				completeTarget: true,
				target: channel.name
			)
		}
	}

	@objc func memberKillFromServer(_ sender: Any?) {
		performOperatorCommand(
			"KILL",
			reason: Preferences.Commands.irCopKillMessage.value,
			sender: sender ?? NSNull()
		)
	}

	@objc func memberShunOnServer(_ sender: Any?) {
		performOperatorCommand(
			"SHUN",
			reason: Preferences.Commands.irCopShunMessage.value,
			sender: sender ?? NSNull()
		)
	}

	@objc func memberBanFromServer(_ sender: Any?) {
		performGline(sender: sender ?? NSNull())
	}

	@objc func memberSetVirtualHost(_ sender: Any?) {
		showSetVirtualHostPrompt(sender: sender ?? NSNull())
	}

	@objc func memberSendFileRequest(_ sender: Any?) {
		showFilePicker(sender: sender ?? NSNull())
	}

	func memberInMemberListDoubleClicked(_ sender: Any) {
		guard mainWindow.memberList.primaryInteractedMember != nil else { return }
		performDoubleClick(sender: sender)
	}

	func memberInChannelViewDoubleClicked(_ sender: Any?) {
		performDoubleClick(sender: sender ?? NSNull())
	}
}

private extension MenuActionController {
	func performIgnore(sender: Any, remove: Bool) {
		guard let client = selectedClient, let channel = selectedChannel,
		      let nickname = selectedNicknames(for: sender).first
		else { return }
		deselectMembers(for: sender)
		let command = remove ? MenuMemberCommand.unignore(nickname) : MenuMemberCommand.ignore(nickname)
		client.sendCommand(command, completeTarget: true, target: channel.name)
	}

	func modifyIgnore(sender: Any) {
		guard let client = selectedClient else { return }
		let selectedMembers = selectedMembers(for: sender)
		deselectMembers(for: sender)
		guard selectedMembers.count == 1,
		      let hostmask = selectedMembers.first?.user.hostmask
		else { return }
		let ignores = client.findIgnores(forHostmask: hostmask)
		if ignores.count == 1 {
			presentServerProperties(for: client, at: .editIgnoreEntry(ignores[0]))
		} else {
			presentServerProperties(for: client, at: .addressBook)
		}
	}

	func performDoubleClick(sender: Any) {
		switch Preferences.Input.userDoubleClickAction.value {
		case .whois:
			memberSendWhois(sender)
		case .privateMessage:
			memberStartPrivateMessage(sender)
		case .insertTextField:
			insertNicknames(sender: sender)
		@unknown default:
			break
		}
	}

	func insertNicknames(sender: Any) {
		guard selectedClient != nil, selectedChannel != nil else { return }
		let nicknames = selectedNicknames(for: sender)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender)

		guard let textView = mainWindow.inputTextField else { return }
		let selectedRange = textView.selectedRange
		var insertion = ""
		if selectedRange.location > 0 {
			/* selectedRange is measured in UTF-16 code units, so it must be
			 read back through NSString. Feeding it to String.index(_:offsetBy:)
			 counts Characters and lands on the wrong one — or traps — as soon
			 as the field holds an emoji. */
			let text = textView.stringValue as NSString
			let previous = text.character(at: selectedRange.location - 1)
			/* A surrogate half is never whitespace, so nil reads as false. */
			let isWhitespace = Unicode.Scalar(previous).map { scalar in
				CharacterSet.whitespacesAndNewlines.contains(scalar)
			} ?? false
			if isWhitespace == false {
				insertion.append(" ")
			}
		}
		insertion += nicknames.joined(separator: ", ")
		insertion += Preferences.Input.tabCompletionSuffix.storedValue ?? ""
		/* Through the editing pair, so the bar resizes, the placeholder hides,
		 the typing state is sent and the insertion is undoable. */
		guard textView.shouldChangeText(in: selectedRange, replacementString: insertion) else { return }
		textView.replaceCharacters(in: selectedRange, with: insertion)
		/* The text that was there is gone: what has to be recoloured is what
		 replaced it. Reusing the pre-edit range walks off the end of a storage
		 the replacement shrank -- select eleven characters, insert a nickname
		 shorter than that, and the range check throws. */
		textView.resetFontColor(
			in: MenuInsertionRangePolicy.insertedRange(replacing: selectedRange, with: insertion)
		)
		textView.didChangeText()
		textView.focus()
	}

	func performForNicknames(sender: Any, action: (Client, String) -> Void) {
		guard let client = selectedClient, selectedChannel != nil else { return }
		for nickname in selectedNicknames(for: sender) {
			action(client, nickname)
		}
		deselectMembers(for: sender)
	}

	func startPrivateMessages(sender: Any) {
		guard let client = selectedClient, selectedChannel != nil else { return }
		for nickname in selectedNicknames(for: sender) {
			guard let query = client.findChannelOrCreate(nickname, isPrivateMessage: true) else { continue }
			mainWindow.select(query)
		}
		deselectMembers(for: sender)
	}

	func performCTCP(_ command: String, sender: Any) {
		performForNicknames(sender: sender) { $0.sendCTCPQuery($1, command: command, text: nil) }
	}

	func performMode(_ command: String, sender: Any) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		let nicknames = selectedNicknames(for: sender)
		deselectMembers(for: sender)
		client.sendCommand(
			MenuMemberCommand.mode(command, nicknames: nicknames),
			completeTarget: true,
			target: channel.name
		)
	}

	func performChannelModeration(
		sender: Any,
		action: (Client, Channel, String) -> Void
	) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		for nickname in selectedNicknames(for: sender) {
			action(client, channel, nickname)
		}
		deselectMembers(for: sender)
	}

	func performOperatorCommand(_ command: String, reason: String, sender: Any) {
		guard let client = selectedClient, selectedChannel != nil, client.isLoggedIn else { return }
		for nickname in selectedNicknames(for: sender) {
			client.sendCommand(MenuMemberCommand.operatorCommand(command, nickname: nickname, reason: reason))
		}
		deselectMembers(for: sender)
	}

	func performGline(sender: Any) {
		guard let client = selectedClient, let channel = selectedChannel, client.isLoggedIn else { return }
		for nickname in selectedNicknames(for: sender) {
			if client.nicknameIsMyself(nickname) {
				client.printDebugInformation(
					String(localized: .IRC.glasstualHasPreventedYouFromBanning(client.serverAddress ?? "")),
					in: channel
				)
				continue
			}
			client.sendCommand(MenuMemberCommand.operatorCommand(
				"GLINE",
				nickname: nickname,
				reason: Preferences.Commands.irCopGlineMessage.value
			))
		}
		deselectMembers(for: sender)
	}

	func showSetVirtualHostPrompt(sender: Any) {
		guard let client = selectedClient, selectedChannel != nil, client.isLoggedIn else { return }
		let nicknames = selectedNicknames(for: sender)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender)
		InputPrompt.present(InputPromptRequest(
			title: PromptStrings.VirtualHost.title,
			message: PromptStrings.VirtualHost.body,
			placeholder: PromptStrings.VirtualHost.placeholder,
			submitButtonTitle: PromptStrings.Action.confirmation,
			cancelButtonTitle: PromptStrings.Action.cancel
		)) { outcome in
			guard case let .submitted(input) = outcome else { return }
			let vhost = input.firstToken
			guard vhost.isEmpty == false else { return }
			for nickname in nicknames {
				client.sendCommand(
					MenuMemberCommand.setVhost(vhost, nickname: nickname),
					completeTarget: false,
					target: nil
				)
			}
		}
	}

	func showFilePicker(sender: Any) {
		guard let client = selectedClient, selectedChannel != nil, client.isLoggedIn else { return }
		let nicknames = selectedNicknames(for: sender)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender)
		mainWindow.presentationModel.chooseTransferFiles { [weak self] urls in
			guard let self, client.isLoggedIn else { return }
			for nickname in nicknames {
				for url in urls {
					fileTransferCenter.offerSender(
						for: client,
						nickname: nickname,
						path: url.path,
						autoOpen: true,
						accessURL: url
					)
				}
			}
		}
	}
}

// MARK: - Dropped files

extension MenuActionController {
	func sendDroppedFilesToSelectedChannel(_ files: [String]) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isPrivateMessage
		else { return }
		sendDroppedFiles(files, nickname: channel.name)
	}

	func sendDroppedFiles(_ files: [String], nickname: String) {
		guard let client = selectedClient, client.isLoggedIn else { return }
		for file in files {
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: file, isDirectory: &isDirectory),
			      isDirectory.boolValue == false
			else { continue }
			fileTransferCenter.offerSender(for: client, nickname: nickname, path: file, autoOpen: true)
		}
	}
}

// MARK: - Navigation

extension MenuActionController {
	func navigateToTreeItem(at url: URL) {
		let identifier = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard identifier.isEmpty == false else { return }
		navigateToTreeItem(withIdentifier: identifier)
	}

	func navigateToTreeItem(withIdentifier identifier: String) {
		guard identifier.count == 36,
		      let item = clientDirectory?.findItem(withId: identifier)
		else { return }
		navigateToTreeItem(item)
	}

	func navigateToTreeItem(_ item: ChatItem) {
		mainWindow.select(item)
	}

	/** The Navigation menu's list of every channel.

	 No key equivalents: the list is ordered by where a channel happens to sit
	 in the sidebar, so ⌘1 meant a different conversation as soon as a server
	 connected or a channel was joined — and it took the digits the Window menu
	 names windows with. */
	func populateNavigationChannelList() {
		let menu = mainMenuNavigationChannelListMenu
		guard let clientDirectory else { return }
		menu.removeAllItems()
		for client in clientDirectory.clientList {
			let submenu = NSMenu()
			let clientItem = NSMenuItem()
			clientItem.title = client.name
			clientItem.submenu = submenu
			for channel in client.channelList {
				let item = NSMenuItem(
					title: channel.name,
					action: #selector(navigateToChannelInNavigationList(_:)),
					keyEquivalent: ""
				)
				item.target = self
				item.userInfoString = clientDirectory.pasteboardString(for: channel)
				submenu.addItem(item)
			}
			menu.addItem(clientItem)
		}
	}

	@objc func navigateToChannelInNavigationList(_ sender: NSMenuItem) {
		guard let pasteboardString = sender.userInfoString,
		      let item = clientDirectory?.findItem(withPasteboardString: pasteboardString)
		else { return }
		mainWindow.select(item)
	}

	@objc func performNavigationAction(_ sender: Any?) {
		guard selectedClient != nil,
		      let menuItem = sender as? NSMenuItem,
		      let action = Self.navigationAction(for: menuItem.command)
		else { return }
		perform(action)
	}

	@objc func onNextHighlight(_: Any?) {
		moveHighlightOrScrollback(for: .nextHighlight)
	}

	@objc func onPreviousHighlight(_: Any?) {
		moveHighlightOrScrollback(for: .previousHighlight)
	}

	@objc func jumpToCurrentSession(_: Any?) {
		moveHighlightOrScrollback(for: .jumpToCurrentSession)
	}

	@objc func jumpToPresent(_: Any?) {
		moveHighlightOrScrollback(for: .jumpToPresent)
	}

	/// The menu items used to be dispatched by selector string onto the main
	/// window, whose handlers are declared `(NSEvent)` and were handed an
	/// `NSMenuItem`. They are called directly now, with no event.
	static func navigationAction(for command: MenuCommand?) -> MenuNavigationAction? {
		switch command {
		case .nextServer: .nextServer
		case .previousServer: .previousServer
		case .nextActiveServer: .nextActiveServer
		case .previousActiveServer: .previousActiveServer
		case .nextChannel: .nextChannel
		case .previousChannel: .previousChannel
		case .nextActiveChannel: .nextActiveChannel
		case .previousActiveChannel: .previousActiveChannel
		case .nextUnreadChannel: .nextUnreadChannel
		case .previousUnreadChannel: .previousUnreadChannel
		case .moveBackward: .moveBackward
		case .moveForward: .moveForward
		case .previousSelection: .previousSelection
		default: nil
		}
	}

	func moveHighlightOrScrollback(for command: MenuCommand?) {
		guard let controller = selectedViewController else { return }
		switch command {
		case .nextHighlight: controller.nextHighlight()
		case .previousHighlight: controller.previousHighlight()
		case .jumpToCurrentSession: controller.jumpToCurrentSession()
		case .jumpToPresent: controller.jumpToPresent()
		default: break
		}
	}

	private func perform(_ action: MenuNavigationAction) {
		switch action {
		case .nextServer: mainWindow.selectNextServer(nil)
		case .previousServer: mainWindow.selectPreviousServer(nil)
		case .nextActiveServer: mainWindow.selectNextActiveServer(nil)
		case .previousActiveServer: mainWindow.selectPreviousActiveServer(nil)
		case .nextChannel: mainWindow.selectNextChannel(nil)
		case .previousChannel: mainWindow.selectPreviousChannel(nil)
		case .nextActiveChannel: mainWindow.selectNextActiveChannel(nil)
		case .previousActiveChannel: mainWindow.selectPreviousActiveChannel(nil)
		case .nextUnreadChannel: mainWindow.selectNextUnreadChannel(nil)
		case .previousUnreadChannel: mainWindow.selectPreviousUnreadChannel(nil)
		case .moveBackward: mainWindow.selectPreviousWindow(nil)
		case .moveForward: mainWindow.selectNextWindow(nil)
		case .previousSelection: mainWindow.selectPreviousSelection(nil)
		}
	}
}

/** The menus the connection tree feeds. The directory tells the controller when
 the shape of that tree changed rather than being called into. */
extension MenuActionController: ClientDirectoryObserver {
	func clientDirectoryNavigationListDidChange(_: ClientDirectory) {
		populateNavigationChannelList()
	}

	func clientDirectoryPreferencesDidChange(_: ClientDirectory) {
		preferencesChanged()
	}
}

/// The sheets the IRC layer raises, and the one folder it asks to be shown.
extension MenuActionController: ClientMenuPresenting {
	func revealInFinder(_ url: URL) {
		NSWorkspace.shared.open(url)
	}

	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool) {
		setNotificationSoundsMuted(muted)
	}

	func showServerPropertiesSheet(for client: Client, selection: ServerPropertiesDestination) {
		presentServerProperties(for: client, at: selection)
	}

	func showNicknameColorSheet(forNickname nickname: String) {
		showNicknameColorSheet(for: nickname)
	}
}
