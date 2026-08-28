/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

enum MenuNavigationTag {
	static let nextServer = 7_000_000
	static let previousServer = 7_000_001
	static let nextActiveServer = 7_000_003
	static let previousActiveServer = 7_000_004
	static let nextChannel = 7_010_000
	static let previousChannel = 7_010_001
	static let nextActiveChannel = 7_010_003
	static let previousActiveChannel = 7_010_004
	static let nextUnreadChannel = 7_010_006
	static let previousUnreadChannel = 7_010_007
	static let moveBackward = 703
	static let moveForward = 704
	static let previousSelection = 706
	static let nextHighlight = 708
	static let previousHighlight = 709
	static let jumpToCurrentSession = 711
	static let jumpToPresent = 712
}

@MainActor
@objc(TXMenuActionCoordinator)
public final class MenuActionCoordinator: NSObject {
	weak var menuController: TXMenuController?
	var menuIsOpen = false
	var menuPerformedActionLastOpen = false
	weak var pointedClient: IRCClient?
	weak var pointedChannel: IRCChannel?
	var currentSearchPhrase = ""
	var reactionPopover: ReactionPopoverController?

	@objc(initWithMenuController:)
	public init(menuController: TXMenuController) {
		self.menuController = menuController
		super.init()
	}

	var mainWindow: TVCMainWindow {
		AppController.shared.mainWindow
	}

	var selectedClient: IRCClient? {
		pointedClient ?? mainWindow.selectedClient
	}

	var selectedChannel: IRCChannel? {
		pointedChannel ?? mainWindow.selectedChannel
	}

	private var fileTransferController: TDCFileTransferDialog {
		SharedApplication.sharedFileTransferDialog()
	}

	@objc(selectedMembersForSender:returnNicknames:)
	public func selectedMembers(for sender: Any, returnNicknames: Bool) -> [Any] {
		guard let controller = menuController,
		      let client = selectedClient,
		      let channel = selectedChannel,
		      client.isLoggedIn,
		      channel.isActive
		else {
			return []
		}

		let pointedNickname: String? = if let menuItem = sender as? NSMenuItem {
			menuItem.textualUserInfo
		} else {
			controller.pointedNickname
		}

		if let pointedNickname {
			if returnNicknames {
				return [pointedNickname]
			}
			return channel.findMember(pointedNickname).map { [$0] } ?? []
		}

		return mainWindow.memberList.selectedRowIndexes.compactMap { row in
			guard let member = mainWindow.memberList.item(atRow: row) as? ChannelUser else {
				return nil
			}
			return returnNicknames ? member.user.nickname : member
		}
	}

	@objc(deselectMembersForSender:)
	public func deselectMembers(for sender: Any) {
		if let menuItem = sender as? NSMenuItem,
		   menuItem.textualUserInfo?.isEmpty == false
		{
			return
		}
		if menuController?.pointedNickname != nil {
			menuController?.pointedNickname = nil
			return
		}
		mainWindow.memberList.deselectAll(sender)
	}

	private func nicknames(for sender: Any) -> [String] {
		selectedMembers(for: sender, returnNicknames: true) as? [String] ?? []
	}

	private func members(for sender: Any) -> [ChannelUser] {
		selectedMembers(for: sender, returnNicknames: false) as? [ChannelUser] ?? []
	}

	@objc(performMemberAction:sender:)
	public func performMemberAction(_ action: TXMenuMemberAction, sender: Any?) {
		let sender = sender ?? NSNull()
		switch action {
		case .addIgnore:
			performIgnore(sender: sender, remove: false)
		case .removeIgnore:
			performIgnore(sender: sender, remove: true)
		case .modifyIgnore:
			modifyIgnore(sender: sender)
		case .memberListDoubleClick:
			guard mainWindow.memberList.rowBeneathMouse >= 0 else { return }
			performDoubleClick(sender: sender)
		case .channelViewDoubleClick:
			performDoubleClick(sender: sender)
		case .insertNickname:
			insertNicknames(sender: sender)
		case .whois:
			performForNicknames(sender: sender) { $0.sendWhois($1) }
		case .privateMessage:
			startPrivateMessages(sender: sender)
		case .ctcpPing:
			performForNicknames(sender: sender) { $0.sendCTCPPing($1) }
		case .ctcpFinger:
			performCTCP("FINGER", sender: sender)
		case .ctcpTime:
			performCTCP("TIME", sender: sender)
		case .ctcpVersion:
			performCTCP("VERSION", sender: sender)
		case .ctcpUserinfo:
			performCTCP("USERINFO", sender: sender)
		case .ctcpClientInfo:
			performCTCP("CLIENTINFO", sender: sender)
		case .changeColor:
			changeColorForSelectedMember(sender: sender)
		case .giveOp, .takeOp, .giveHalfop, .takeHalfop, .giveVoice, .takeVoice,
		     .kick, .ban, .kickban, .kill, .gline, .shun, .setVhost, .sendFile:
			performModerationAction(action, sender: sender)
		@unknown default:
			break
		}
	}

	private func performModerationAction(_ action: TXMenuMemberAction, sender: Any) {
		switch action {
		case .giveOp:
			performMode("OP", sender: sender)
		case .takeOp:
			performMode("DEOP", sender: sender)
		case .giveHalfop:
			performMode("HALFOP", sender: sender)
		case .takeHalfop:
			performMode("DEHALFOP", sender: sender)
		case .giveVoice:
			performMode("VOICE", sender: sender)
		case .takeVoice:
			performMode("DEVOICE", sender: sender)
		case .kick:
			performChannelModeration(sender: sender) { client, channel, nickname in
				client.kick(nickname, in: channel)
			}
		case .ban:
			performChannelModeration(sender: sender) { client, channel, nickname in
				client.sendCommand("BAN \(nickname)", completeTarget: true, target: channel.name)
			}
		case .kickban:
			performChannelModeration(sender: sender) { client, channel, nickname in
				client.sendCommand(
					MenuMemberCommand.kickban(nickname, reason: TextualPreferences.defaultKickMessage()),
					completeTarget: true,
					target: channel.name
				)
			}
		case .kill:
			performOperatorCommand("KILL", reason: TextualPreferences.irCopDefaultKillMessage(), sender: sender)
		case .gline:
			performGline(sender: sender)
		case .shun:
			performOperatorCommand("SHUN", reason: TextualPreferences.irCopDefaultShunMessage(), sender: sender)
		case .setVhost:
			showSetVhostPrompt(sender: sender)
		case .sendFile:
			showFilePicker(sender: sender)
		case .addIgnore, .removeIgnore, .modifyIgnore, .memberListDoubleClick,
		     .channelViewDoubleClick, .insertNickname, .whois, .privateMessage,
		     .ctcpPing, .ctcpFinger, .ctcpTime, .ctcpVersion, .ctcpUserinfo,
		     .ctcpClientInfo:
			break
		@unknown default:
			break
		}
	}

	private func performIgnore(sender: Any, remove: Bool) {
		guard let client = selectedClient, let channel = selectedChannel,
		      let nickname = nicknames(for: sender).first
		else { return }
		deselectMembers(for: sender)
		let command = remove ? MenuMemberCommand.unignore(nickname) : MenuMemberCommand.ignore(nickname)
		client.sendCommand(command, completeTarget: true, target: channel.name)
	}

	private func modifyIgnore(sender: Any) {
		guard let client = selectedClient else { return }
		let selectedMembers = members(for: sender)
		deselectMembers(for: sender)
		guard selectedMembers.count == 1,
		      let hostmask = selectedMembers.first?.user.hostmask
		else { return }
		let ignores = client.findIgnores(forHostmask: hostmask)
		if ignores.count == 1 {
			menuController?.showServerPropertiesSheet(
				for: client,
				selection: MenuDialogSelection.serverNewIgnoreEntry,
				context: ignores[0]
			)
		} else {
			menuController?.showServerPropertiesSheet(
				for: client,
				selection: MenuDialogSelection.serverAddressBook,
				context: nil
			)
		}
	}

	private func performDoubleClick(sender: Any) {
		switch TextualPreferences.userDoubleClickOption() {
		case .whois:
			performMemberAction(.whois, sender: sender)
		case .privateMessage:
			performMemberAction(.privateMessage, sender: sender)
		case .insertTextField:
			performMemberAction(.insertNickname, sender: sender)
		@unknown default:
			break
		}
	}

	private func insertNicknames(sender: Any) {
		guard selectedClient != nil, selectedChannel != nil else { return }
		let nicknames = nicknames(for: sender)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender)

		let textView = mainWindow.inputTextField!
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
		insertion += TextualPreferences.tabCompletionSuffix() ?? ""
		textView.replaceCharacters(in: selectedRange, with: insertion)
		textView.resetFontColor(in: selectedRange)
		textView.focus()
	}

	private func changeColorForSelectedMember(sender: Any) {
		guard selectedClient != nil, selectedChannel != nil,
		      let nickname = nicknames(for: sender).first
		else { return }

		showNicknameColorSheet(for: nickname)
	}

	private func performForNicknames(sender: Any, action: (IRCClient, String) -> Void) {
		guard let client = selectedClient, selectedChannel != nil else { return }
		for nickname in nicknames(for: sender) {
			action(client, nickname)
		}
		deselectMembers(for: sender)
	}

	private func startPrivateMessages(sender: Any) {
		guard let client = selectedClient, selectedChannel != nil else { return }
		for nickname in nicknames(for: sender) {
			guard let query = client.findChannelOrCreate(nickname, isPrivateMessage: true) else { continue }
			guard let treeItem = (query as AnyObject) as? IRCTreeItem else { continue }
			mainWindow.select(treeItem)
		}
		deselectMembers(for: sender)
	}

	private func performCTCP(_ command: String, sender: Any) {
		performForNicknames(sender: sender) { $0.sendCTCPQuery($1, command: command, text: nil) }
	}

	private func performMode(_ command: String, sender: Any) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		let nicknames = nicknames(for: sender)
		deselectMembers(for: sender)
		client.sendCommand(
			MenuMemberCommand.mode(command, nicknames: nicknames),
			completeTarget: true,
			target: channel.name
		)
	}

	private func performChannelModeration(
		sender: Any,
		action: (IRCClient, IRCChannel, String) -> Void
	) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isChannel
		else { return }
		for nickname in nicknames(for: sender) {
			action(client, channel, nickname)
		}
		deselectMembers(for: sender)
	}

	private func performOperatorCommand(_ command: String, reason: String, sender: Any) {
		guard let client = selectedClient, selectedChannel != nil, client.isLoggedIn else { return }
		for nickname in nicknames(for: sender) {
			client.sendCommand(MenuMemberCommand.operatorCommand(command, nickname: nickname, reason: reason))
		}
		deselectMembers(for: sender)
	}

	private func performGline(sender: Any) {
		guard let client = selectedClient, let channel = selectedChannel, client.isLoggedIn else { return }
		for nickname in nicknames(for: sender) {
			if client.nicknameIsMyself(nickname) {
				client.printDebugInformation(
					IRCCommandStrings.preventedSelfBan(serverAddress: client.serverAddress ?? ""),
					in: channel
				)
				continue
			}
			client.sendCommand(MenuMemberCommand.operatorCommand(
				"GLINE",
				nickname: nickname,
				reason: TextualPreferences.irCopDefaultGlineMessage()
			))
		}
		deselectMembers(for: sender)
	}

	private func showSetVhostPrompt(sender: Any) {
		guard let client = selectedClient, selectedChannel != nil, client.isLoggedIn else { return }
		let nicknames = nicknames(for: sender)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender)
		InputPrompt.prompt(
			withMessage: PromptStrings.VirtualHost.body,
			title: PromptStrings.VirtualHost.title,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: PromptStrings.Action.cancel,
			prefillString: nil
		) { response, input in
			let vhost = input.firstToken
			guard response == .alertFirstButtonReturn, vhost.isEmpty == false else { return }
			for nickname in nicknames {
				client.sendCommand(
					MenuMemberCommand.setVhost(vhost, nickname: nickname),
					completeTarget: false,
					target: nil
				)
			}
		}
	}

	private func showFilePicker(sender: Any) {
		guard let client = selectedClient, selectedChannel != nil, client.isLoggedIn else { return }
		let nicknames = nicknames(for: sender)
		guard nicknames.isEmpty == false else { return }
		deselectMembers(for: sender)
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.canCreateDirectories = false
		panel.resolvesAliases = true
		panel.beginSheetModal(for: mainWindow) { [weak self] response in
			guard response == .OK, let self else { return }
			fileTransferController.fileTransferTable.beginUpdates()
			defer { fileTransferController.fileTransferTable.endUpdates() }
			for nickname in nicknames {
				for url in panel.urls {
					_ = fileTransferController.addSender(
						for: client,
						nickname: nickname,
						path: url.path,
						autoOpen: true
					)
				}
			}
		}
	}

	@objc(sendDroppedFilesToSelectedChannel:)
	public func sendDroppedFilesToSelectedChannel(_ files: [String]) {
		guard let client = selectedClient, let channel = selectedChannel,
		      client.isLoggedIn, channel.isPrivateMessage
		else { return }
		sendDroppedFiles(files, nickname: channel.name)
	}

	@objc(sendDroppedFiles:row:)
	public func sendDroppedFiles(_ files: [String], row: UInt) {
		// The member list is only ever populated for channels, so no
		// isPrivateMessage check here: the file goes to the row's nickname.
		guard let client = selectedClient, client.isLoggedIn,
		      let member = mainWindow.memberList.item(atRow: Int(row)) as? ChannelUser
		else { return }
		sendDroppedFiles(files, nickname: member.user.nickname)
	}

	@objc(sendDroppedFiles:nickname:)
	public func sendDroppedFiles(_ files: [String], nickname: String) {
		guard let client = selectedClient, client.isLoggedIn else { return }
		fileTransferController.fileTransferTable.beginUpdates()
		defer { fileTransferController.fileTransferTable.endUpdates() }
		for file in files {
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: file, isDirectory: &isDirectory),
			      isDirectory.boolValue == false
			else { continue }
			_ = fileTransferController.addSender(for: client, nickname: nickname, path: file, autoOpen: true)
		}
	}

	@objc(navigateToTreeItemAtURL:)
	public func navigateToTreeItem(at url: URL) {
		let identifier = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard identifier.isEmpty == false else { return }
		navigateToTreeItem(withIdentifier: identifier)
	}

	@objc(navigateToTreeItemWithIdentifier:)
	public func navigateToTreeItem(withIdentifier identifier: String) {
		guard identifier.count == 36,
		      let item = AppController.shared.world.findItem(withId: identifier)
		else { return }
		navigateToTreeItem(item)
	}

	@objc(navigateToTreeItem:)
	public func navigateToTreeItem(_ item: IRCTreeItem) {
		mainWindow.select(item)
	}

	@objc
	public func populateNavigationChannelList() {
		guard let menu = menuController?.mainMenuNavigationChannelListMenu else { return }
		menu.removeAllItems()
		var channelCount = 0
		for client in AppController.shared.world.clientList {
			let submenu = NSMenu()
			let clientItem = NSMenuItem()
			clientItem.title = client.name
			clientItem.submenu = submenu
			for channel in client.channelList {
				let item = NSMenuItem(
					title: channel.name,
					action: NSSelectorFromString("_navigateToChannelInNavigationList:"),
					keyEquivalent: channelCount < 10 ? String((channelCount + 1) % 10) : ""
				)
				item.target = menuController
				if channelCount < 10 {
					item.keyEquivalentModifierMask = .command
				}
				if let treeItem = (channel as AnyObject) as? IRCTreeItem {
					item.textualUserInfo = AppController.shared.world.pasteboardString(for: treeItem)
				}
				submenu.addItem(item)
				channelCount += 1
			}
			menu.addItem(clientItem)
		}
	}

	@objc(navigateToChannelInNavigationList:)
	public func navigateToChannelInNavigationList(_ sender: NSMenuItem) {
		guard let pasteboardString = sender.textualUserInfo,
		      let item = AppController.shared.world.findItem(withPasteboardString: pasteboardString)
		else { return }
		mainWindow.select(item)
	}

	@objc(performNavigationAction:)
	public func performNavigationAction(_ sender: Any?) {
		guard selectedClient != nil, let menuItem = sender as? NSMenuItem,
		      let selector = Self.navigationSelector(for: menuItem.tag)
		else { return }
		mainWindow.perform(selector, with: sender)
	}

	static func navigationSelector(for tag: Int) -> Selector? {
		let selectorName: String? = switch tag {
		case MenuNavigationTag.nextServer: "selectNextServer:"
		case MenuNavigationTag.previousServer: "selectPreviousServer:"
		case MenuNavigationTag.nextActiveServer: "selectNextActiveServer:"
		case MenuNavigationTag.previousActiveServer: "selectPreviousActiveServer:"
		case MenuNavigationTag.nextChannel: "selectNextChannel:"
		case MenuNavigationTag.previousChannel: "selectPreviousChannel:"
		case MenuNavigationTag.nextActiveChannel: "selectNextActiveChannel:"
		case MenuNavigationTag.previousActiveChannel: "selectPreviousActiveChannel:"
		case MenuNavigationTag.nextUnreadChannel: "selectNextUnreadChannel:"
		case MenuNavigationTag.previousUnreadChannel: "selectPreviousUnreadChannel:"
		case MenuNavigationTag.moveBackward: "selectPreviousWindow:"
		case MenuNavigationTag.moveForward: "selectNextWindow:"
		case MenuNavigationTag.previousSelection: "selectPreviousSelection:"
		default: nil
		}
		return selectorName.map(NSSelectorFromString)
	}

	@objc(moveHighlightOrScrollbackForTag:)
	public func moveHighlightOrScrollback(forTag tag: Int) {
		guard let legacyController = selectedChannel?.viewController ?? selectedClient?.viewController else { return }
		guard let controller = (legacyController as AnyObject) as? LogController else { return }
		switch tag {
		case MenuNavigationTag.nextHighlight: controller.nextHighlight()
		case MenuNavigationTag.previousHighlight: controller.previousHighlight()
		case MenuNavigationTag.jumpToCurrentSession: controller.jumpToCurrentSession()
		case MenuNavigationTag.jumpToPresent: controller.jumpToPresent()
		default: break
		}
	}
}
