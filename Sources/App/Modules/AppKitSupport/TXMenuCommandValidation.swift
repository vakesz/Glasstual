/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
import GlasstualPluginKit

private enum CommandMenuTag {
	static let mainChannel = 6
	static let mainQuery = 7
	static let closeWindow = 205
	static let paste = 305
	static let markScrollback = 400
	static let scrollbackMarker = 401
	static let markAllRead = 403
	static let clearScrollback = 404
	static let increaseFont = 406
	static let decreaseFont = 407
	static let connect = 500
	static let connectWithoutProxy = 501
	static let disconnect = 502
	static let cancelReconnect = 503
	static let channelList = 505
	static let changeNickname = 506
	static let duplicateServer = 509
	static let deleteServer = 510
	static let addChannelToServer = 512
	static let serverProperties = 514
	static let joinChannel = 600
	static let leaveChannel = 601
	static let leaveChannelSeparator = 602
	static let addChannel = 603
	static let viewChannelLogs = 606
	static let modifyTopic = 608
	static let modes = 609
	static let bans = 611
	static let banExceptions = 612
	static let inviteExceptions = 613
	static let quiets = 614
	static let nextHighlight = 708
	static let previousHighlight = 709
	static let jumpToCurrentSession = 711
	static let jumpToPresent = 712
	static let toggleMemberList = 803
	static let toggleServerList = 804
	static let toggleAppearance = 805
	static let toggleAppearanceSeparator = 806
	static let sortChannelList = 807
	static let sortChannelListSeparator = 808
	static let centerWindow = 809
	static let resetWindow = 810
	static let resetWindowSeparator = 811
	static let mainWindow = 812
	static let addressBook = 813
	static let ignoreList = 814
	static let viewLogs = 815
	static let highlightList = 816
	static let webChangeNickname = 1200
	static let webSearch = 1202
	static let webDictionary = 1203
	static let webCopy = 1205
	static let webPaste = 1206
	static let webPasteSeparator = 1207
	static let webQueryLogs = 1208
	static let webChannelMenu = 1209
	static let webReply = 1211
	static let webReact = 1212
	static let segmentedAddChannel = 1302
	static let addIgnore = 1600
	static let modifyIgnore = 1601
	static let removeIgnore = 1602
	static let inviteTo = 1604
	static let whois = 1606
	static let privateMessage = 1607
	static let giveOp = 1609
	static let giveHalfop = 1610
	static let giveVoice = 1611
	static let allModesGiven = 1612
	static let allModesGivenSeparator = 1613
	static let takeOp = 1614
	static let takeHalfop = 1615
	static let takeVoice = 1616
	static let allModesTaken = 1617
	static let allModesTakenSeparator = 1618
	static let ban = 1619
	static let kick = 1620
	static let kickban = 1621
	static let kickbanSeparator = 1622
	static let ctcp = 1623
	static let ircOperator = 1624
	static let changeColor = 1625
	static let developerMode = 9_100_000
}

@MainActor
extension MenuActionCoordinator {
	private var selectedViewController: LogController? {
		if let controller = selectedChannel?.viewController {
			return controller
		}

		return (selectedClient?.viewController as AnyObject?) as? LogController
	}

	private var selectedBackingView: LogView? {
		selectedViewController?.backingView
	}

	@objc(validateMenuItem:)
	public func validate(_ menuItem: NSMenuItem) -> Bool {
		let appController: ApplicationController = AppController.shared
		guard appController.applicationIsTerminating == false else { return false }

		return MenuValidationPolicy.validate(
			tag: menuItem.tag,
			commandSpecificResult: validateCommand(menuItem),
			applicationIsLaunched: appController.applicationIsLaunched,
			mainWindowHasAttachedSheet: mainWindow.attachedSheet != nil,
			mainWindowIsFocused: mainWindow.isMainWindow,
			mainWindowIsBeneathMouse: mainWindow.ceIsBeneathMouse
		)
	}

	private func validateCommand(_ item: NSMenuItem) -> Bool {
		switch item.tag {
		case 500 ... 599:
			validateServerCommand(item)
		case 600 ... 699:
			validateChannelCommand(item)
		case 800 ... 899:
			validateWindowCommand(item)
		case 1200 ... 1299:
			validateWebCommand(item)
		case 1600 ... 1699:
			validateMemberCommand(item)
		default:
			validateGeneralCommand(item)
		}
	}

	private func validateGeneralCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.tag {
		case CommandMenuTag.mainChannel:
			let visible = channel?.isChannel == true
			item.isHidden = visible == false
			item.submenu = visible ? menuController?.mainMenuChannelMenu : nil
			return true
		case CommandMenuTag.mainQuery:
			let visible = channel.map { $0.isPrivateMessage || $0.isUtility || $0.isDirectChat } == true
			item.isHidden = visible == false
			item.submenu = visible ? menuController?.mainMenuQueryMenu : nil
			return true
		case CommandMenuTag.closeWindow:
			return validateCloseWindow(item, client: client, channel: channel)
		case CommandMenuTag.paste:
			return validatePaste()
		case CommandMenuTag.markScrollback, CommandMenuTag.scrollbackMarker,
		     CommandMenuTag.markAllRead, CommandMenuTag.clearScrollback,
		     CommandMenuTag.increaseFont, CommandMenuTag.decreaseFont,
		     CommandMenuTag.jumpToCurrentSession, CommandMenuTag.jumpToPresent:
			return selectedViewController != nil
		case CommandMenuTag.nextHighlight, CommandMenuTag.previousHighlight:
			return selectedViewController?.highlightAvailable(
				item.tag == CommandMenuTag.previousHighlight
			) == true
		case CommandMenuTag.segmentedAddChannel:
			return client != nil
		case 1802:
			let isQuery = channel?.isPrivateMessage == true
			item.isHidden = isQuery == false
			item.menu?.item(withTag: 1801)?.isHidden = isQuery == false
			return TextualPreferences.logToDiskIsEnabled()
		case CommandMenuTag.developerMode:
			item.state = TextualPreferences.developerModeEnabled() ? .on : .off
			return true
		default:
			return true
		}
	}

	private func validateServerCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient

		switch item.tag {
		case CommandMenuTag.connect:
			guard let client else {
				item.isHidden = false
				return false
			}
			let connected = client.isConnected || client.isConnecting
			item.isHidden = connected
			return connected == false && client.isQuitting == false
		case CommandMenuTag.connectWithoutProxy:
			let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
			guard flags == .shift, let client else {
				item.isHidden = true
				return false
			}
			let unavailable = client.isConnected || client.isConnecting || client.config.proxyType == .none
			item.isHidden = unavailable
			return unavailable == false && client.isQuitting == false
		case CommandMenuTag.disconnect:
			let connected = client.map { $0.isConnected || $0.isConnecting } == true
			item.isHidden = connected == false
			return connected
		case CommandMenuTag.cancelReconnect:
			let reconnecting = client?.isReconnecting == true
			item.isHidden = reconnecting == false
			return reconnecting
		case CommandMenuTag.channelList:
			return client?.isLoggedIn == true
		case CommandMenuTag.changeNickname:
			return client?.isConnected == true
		case CommandMenuTag.duplicateServer, CommandMenuTag.addChannelToServer,
		     CommandMenuTag.serverProperties:
			return client != nil
		case CommandMenuTag.deleteServer:
			return client.map { $0.isConnecting == false && $0.isConnected == false } == true
		default:
			return true
		}
	}

	private func validateChannelCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.tag {
		case CommandMenuTag.joinChannel:
			item.isHidden = client?.isLoggedIn != true || channel?.isActive == true
			return true
		case CommandMenuTag.leaveChannel:
			item.isHidden = client?.isLoggedIn != true || channel?.isActive != true
			let joinHidden = item.menu?.item(withTag: CommandMenuTag.joinChannel)?.isHidden == true
			item.menu?.item(withTag: CommandMenuTag.leaveChannelSeparator)?.isHidden =
				item.isHidden && joinHidden
			return true
		case CommandMenuTag.addChannel:
			return client != nil
		case CommandMenuTag.viewChannelLogs:
			return TextualPreferences.logToDiskIsEnabled()
		case CommandMenuTag.modifyTopic, CommandMenuTag.modes, CommandMenuTag.bans:
			return client?.isLoggedIn == true && channel?.isActive == true
		case CommandMenuTag.banExceptions:
			item.isHidden = client?.supportInfo.isListSupported(.banException) != true
			return client?.isLoggedIn == true && channel?.isActive == true
		case CommandMenuTag.inviteExceptions:
			item.isHidden = client?.supportInfo.isListSupported(.inviteException) != true
			return client?.isLoggedIn == true && channel?.isActive == true
		case CommandMenuTag.quiets:
			item.isHidden = client?.supportInfo.isListSupported(.quiet) != true
			return client?.isLoggedIn == true && channel?.isActive == true
		default:
			return true
		}
	}

	private func validateWindowCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.tag {
		case CommandMenuTag.toggleServerList, CommandMenuTag.sortChannelList,
		     CommandMenuTag.centerWindow, CommandMenuTag.resetWindow:
			return validateMainWindowCommand(item)
		case CommandMenuTag.mainWindow:
			item.isHidden = mainWindow.isMainWindow
			return mainWindow.isDisabled == false
		case CommandMenuTag.toggleMemberList:
			item.isHidden = mainWindow.isMainWindow == false
			item.title = MainWindowStrings.Menu.memberList(isVisible: mainWindow.isMemberListVisible)
			return channel?.isChannel == true && client?.isLoggedIn == true
		case CommandMenuTag.toggleAppearance:
			item.isHidden = mainWindow.isMainWindow == false
			item.menu?.item(withTag: CommandMenuTag.toggleAppearanceSeparator)?.isHidden = item.isHidden
			return true
		case CommandMenuTag.addressBook, CommandMenuTag.ignoreList:
			item.isHidden = mainWindow.isMainWindow == false
			return client != nil
		case CommandMenuTag.viewLogs:
			return TextualPreferences.logToDiskIsEnabled()
		case CommandMenuTag.highlightList:
			item.isHidden = mainWindow.isMainWindow == false
			return client != nil && TextualPreferences.logHighlights()
		default:
			return true
		}
	}

	private func validateWebCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.tag {
		case CommandMenuTag.webChangeNickname:
			return client?.isConnected == true
		case CommandMenuTag.webSearch:
			guard let webView = selectedBackingView else { return false }
			item.title = ApplicationStrings.search(with: searchProviderName)
			return webView.hasSelection
		case CommandMenuTag.webDictionary:
			return validateDictionaryLookup(item)
		case CommandMenuTag.webCopy:
			return selectedBackingView?.hasSelection == true
		case CommandMenuTag.webPaste:
			return validatePaste()
		case CommandMenuTag.webQueryLogs:
			item.isHidden = channel?.isPrivateMessage != true
			return TextualPreferences.logToDiskIsEnabled()
		case CommandMenuTag.webChannelMenu:
			item.isHidden = channel?.isChannel != true
			let queryLogsHidden = item.menu?.item(withTag: CommandMenuTag.webQueryLogs)?.isHidden == true
			item.menu?.item(withTag: CommandMenuTag.webPasteSeparator)?.isHidden =
				item.isHidden && queryLogsHidden
			return true
		case CommandMenuTag.webReply, CommandMenuTag.webReact:
			return client != nil
				&& channel?.isUtility == false
				&& client?.isCapabilityEnabled(.messageTags) == true
		default:
			return true
		}
	}

	private func validateMemberCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.tag {
		case CommandMenuTag.addIgnore:
			return validateAddIgnore(item, client: client, channel: channel)
		case CommandMenuTag.modifyIgnore, CommandMenuTag.removeIgnore:
			return true
		case CommandMenuTag.inviteTo:
			guard let client, client.isLoggedIn, channel?.isUtility == false else { return false }
			return client.channelList.contains { $0 !== channel && $0.isChannel }
		case CommandMenuTag.whois, CommandMenuTag.ctcp:
			return client?.isLoggedIn == true && channel?.isUtility == false
		case CommandMenuTag.privateMessage:
			item.isHidden = channel?.isChannel != true
			return client?.isLoggedIn == true && channel?.isUtility == false
		case CommandMenuTag.changeColor:
			item.isHidden = channel?.isChannel != true
			return channel?.isChannel == true
		case CommandMenuTag.giveOp, CommandMenuTag.giveHalfop, CommandMenuTag.giveVoice,
		     CommandMenuTag.takeOp, CommandMenuTag.takeHalfop, CommandMenuTag.takeVoice:
			return client?.isLoggedIn == true && channel?.isActive == true
		case CommandMenuTag.allModesGiven:
			return false
		case CommandMenuTag.allModesTaken:
			return validateModeVisibility(item, client: client, channel: channel)
		case CommandMenuTag.ban, CommandMenuTag.kick, CommandMenuTag.kickban:
			let isChannel = channel?.isChannel == true
			item.isHidden = isChannel == false
			item.menu?.item(withTag: CommandMenuTag.kickbanSeparator)?.isHidden = isChannel == false
			return client?.isLoggedIn == true && isChannel && channel?.isActive == true
		case CommandMenuTag.ircOperator:
			item.isHidden = client?.userIsIRCop != true
			return client?.isLoggedIn == true && channel?.isUtility == false
		default:
			return true
		}
	}

	private func validatePaste() -> Bool {
		guard NSPasteboard.general.string(forType: .string)?.isEmpty == false else { return false }
		if mainWindow.isKeyWindow {
			return mainWindow.inputTextField.isEditable
		}
		return (NSApp.keyWindow?.firstResponder as? NSText)?.isEditable == true
	}

	private func validateCloseWindow(_ item: NSMenuItem, client: IRCClient?, channel: IRCChannel?) -> Bool {
		let action = TextualPreferences.commandWKeyAction()
		if action == .closeWindow || mainWindow.isKeyWindow == false {
			item.title = ApplicationStrings.closeWindow
			return true
		}
		guard let client else { return false }

		switch action {
		case .partChannel:
			guard let channel else {
				item.title = ApplicationStrings.closeWindow
				return false
			}
			item.title = channel.isChannel ? ApplicationStrings.leaveChannel : ApplicationStrings.closeQuery
			return channel.isChannel == false || channel.isActive
		case .disconnect:
			item.title = ApplicationStrings.disconnect(from: client.networkNameAlt)
			return client.isConnecting || client.isConnected
		case .terminate:
			item.title = ApplicationStrings.quitApplication
			return true
		default:
			return true
		}
	}

	private func validateMainWindowCommand(_ item: NSMenuItem) -> Bool {
		let isMain = mainWindow.isMainWindow
		item.isHidden = isMain == false

		switch item.tag {
		case CommandMenuTag.toggleServerList:
			item.title = MainWindowStrings.Menu.serverList(isVisible: mainWindow.isServerListVisible)
		case CommandMenuTag.sortChannelList:
			item.menu?.item(withTag: CommandMenuTag.sortChannelListSeparator)?.isHidden = isMain == false
		case CommandMenuTag.resetWindow:
			item.menu?.item(withTag: CommandMenuTag.resetWindowSeparator)?.isHidden = isMain == false
		default:
			break
		}
		return true
	}

	private func validateAddIgnore(_ item: NSMenuItem, client: IRCClient?, channel: IRCChannel?) -> Bool {
		let modify = item.menu?.item(withTag: CommandMenuTag.modifyIgnore)
		let remove = item.menu?.item(withTag: CommandMenuTag.removeIgnore)

		guard channel?.isUtility == false else {
			modify?.isHidden = true
			remove?.isHidden = true
			item.isHidden = false
			return false
		}

		let members = selectedMembers(for: item, returnNicknames: false) as? [ChannelUser] ?? []
		guard members.count == 1, let hostmask = members.first?.user.hostmask, let client else {
			modify?.isHidden = true
			remove?.isHidden = true
			item.isHidden = false
			return false
		}

		let canAdd = client.findIgnores(forHostmask: hostmask).isEmpty
		modify?.isHidden = canAdd
		remove?.isHidden = canAdd
		item.isHidden = canAdd == false
		return true
	}

	private func validateModeVisibility(_ item: NSMenuItem, client: IRCClient?, channel: IRCChannel?) -> Bool {
		func hide(_ tag: Int, _ hidden: Bool) {
			item.menu?.item(withTag: tag)?.isHidden = hidden
		}

		guard channel?.isChannel == true else {
			for tag in [
				CommandMenuTag.giveOp, CommandMenuTag.giveHalfop, CommandMenuTag.giveVoice,
				CommandMenuTag.takeOp, CommandMenuTag.takeHalfop, CommandMenuTag.takeVoice,
				CommandMenuTag.allModesGiven, CommandMenuTag.allModesGivenSeparator,
				CommandMenuTag.allModesTaken, CommandMenuTag.allModesTakenSeparator,
			] {
				hide(tag, true)
			}
			return false
		}

		hide(CommandMenuTag.allModesGivenSeparator, false)
		hide(CommandMenuTag.allModesTakenSeparator, false)
		let members = selectedMembers(for: item, returnNicknames: false) as? [ChannelUser] ?? []

		guard members.count == 1, let user = members.first else {
			for tag in [CommandMenuTag.giveOp, CommandMenuTag.giveHalfop, CommandMenuTag.giveVoice,
			            CommandMenuTag.takeOp, CommandMenuTag.takeHalfop, CommandMenuTag.takeVoice]
			{
				hide(tag, false)
			}
			hide(CommandMenuTag.allModesGiven, true)
			hide(CommandMenuTag.allModesTaken, true)
			return false
		}

		let hasOp = user.ranks.contains(.normalOperator)
		let hasVoice = user.ranks.contains(.voiced)
		let supportsHalfOp = client?.supportInfo.modeSymbolIsUserPrefix("h") == true
		let hasHalfOp = supportsHalfOp && user.ranks.contains(.halfOperator)

		hide(CommandMenuTag.giveOp, hasOp)
		hide(CommandMenuTag.takeOp, hasOp == false)
		hide(CommandMenuTag.giveVoice, hasVoice)
		hide(CommandMenuTag.takeVoice, hasVoice == false)
		hide(CommandMenuTag.giveHalfop, supportsHalfOp == false || hasHalfOp)
		hide(CommandMenuTag.takeHalfop, supportsHalfOp == false || hasHalfOp == false)
		hide(
			CommandMenuTag.allModesGiven,
			hasOp == false || hasVoice == false || (supportsHalfOp && hasHalfOp == false)
		)
		hide(CommandMenuTag.allModesTaken, hasOp || hasHalfOp || hasVoice)
		return false
	}

	private func validateDictionaryLookup(_ item: NSMenuItem) -> Bool {
		guard let selection = selectedBackingView?.selection else { return false }
		let length = selection.count
		guard length > 0, length <= 40 else {
			item.title = ApplicationStrings.lookUpInDictionary
			return false
		}

		let titleSelection = length > 25
			? "\(selection.prefix(24).trimmingCharacters(in: .whitespacesAndNewlines))…"
			: selection
		item.title = ApplicationStrings.lookUpInDictionary(titleSelection)
		return true
	}

	private var searchProviderName: String {
		let services = UserDefaults.standard.dictionary(forKey: "NSPreferredWebServices")
		let provider = services?["NSWebServicesProviderWebSearch"] as? [String: Any]
		return provider?["NSDefaultDisplayName"] as? String ?? "Google"
	}
}
