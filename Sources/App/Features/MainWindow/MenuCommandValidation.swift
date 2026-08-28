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

@MainActor
extension MenuActionCoordinator {
	private var selectedViewController: LogController? {
		if let controller = selectedChannel?.logController {
			return controller
		}

		return selectedClient?.logController
	}

	private var selectedBackingView: LogView? {
		selectedViewController?.backingView
	}

	@objc(validateMenuItem:)
	public func validate(_ menuItem: NSMenuItem) -> Bool {
		let appController: ApplicationController = AppController.shared
		guard appController.applicationIsTerminating == false else { return false }

		return MenuValidationPolicy.validate(
			command: menuItem.command,
			commandSpecificResult: validateCommand(menuItem),
			applicationIsLaunched: appController.applicationIsLaunched,
			mainWindowHasAttachedSheet: mainWindow.attachedSheet != nil,
			mainWindowIsFocused: mainWindow.isMainWindow,
			mainWindowIsBeneathMouse: mainWindow.ceIsBeneathMouse
		)
	}

	private func validateCommand(_ item: NSMenuItem) -> Bool {
		switch item.command?.validationGroup {
		case .server:
			validateServerCommand(item)
		case .channel:
			validateChannelCommand(item)
		case .window:
			validateWindowCommand(item)
		case .web:
			validateWebCommand(item)
		case .member:
			validateMemberCommand(item)
		case .general, nil:
			validateGeneralCommand(item)
		}
	}

	private func validateGeneralCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.command {
		case .channelMenu:
			let visible = channel?.isChannel == true
			item.isHidden = visible == false
			item.submenu = visible ? menuController?.mainMenuChannelMenu : nil
			return true
		case .queryMenu:
			let visible = channel.map { $0.isPrivateMessage || $0.isUtility || $0.isDirectChat } == true
			item.isHidden = visible == false
			item.submenu = visible ? menuController?.mainMenuQueryMenu : nil
			return true
		case .closeWindow:
			return validateCloseWindow(item, client: client, channel: channel)
		case .paste:
			return validatePaste()
		case .markScrollback, .scrollbackMarker,
		     .markAllRead, .clearScrollback,
		     .increaseFont, .decreaseFont,
		     .jumpToCurrentSession, .jumpToPresent:
			return selectedViewController != nil
		case .nextHighlight, .previousHighlight:
			return selectedViewController?.highlightAvailable(
				item.command == .previousHighlight
			) == true
		case .segmentedAddChannel:
			return client != nil
		case .queryLogs:
			let isQuery = channel?.isPrivateMessage == true
			item.isHidden = isQuery == false
			item.menu?.item(for: .closeQuerySeparator)?.isHidden = isQuery == false
			return TextualPreferences.logToDiskIsEnabled()
		case .developerMode:
			item.state = TextualPreferences.developerModeEnabled() ? .on : .off
			return true
		default:
			return true
		}
	}

	private func validateServerCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient

		switch item.command {
		case .connect:
			guard let client else {
				item.isHidden = false
				return false
			}
			let connected = client.isConnected || client.isConnecting
			item.isHidden = connected
			return connected == false && client.isQuitting == false
		case .connectWithoutProxy:
			let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
			guard flags == .shift, let client else {
				item.isHidden = true
				return false
			}
			let unavailable = client.isConnected || client.isConnecting || client.config.proxyType == .none
			item.isHidden = unavailable
			return unavailable == false && client.isQuitting == false
		case .disconnect:
			let connected = client.map { $0.isConnected || $0.isConnecting } == true
			item.isHidden = connected == false
			return connected
		case .cancelReconnect:
			let reconnecting = client?.isReconnecting == true
			item.isHidden = reconnecting == false
			return reconnecting
		case .channelList:
			return client?.isLoggedIn == true
		case .changeNickname:
			return client?.isConnected == true
		case .duplicateServer, .addChannelToServer,
		     .serverProperties:
			return client != nil
		case .deleteServer:
			return client.map { $0.isConnecting == false && $0.isConnected == false } == true
		default:
			return true
		}
	}

	private func validateChannelCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.command {
		case .joinChannel:
			item.isHidden = client?.isLoggedIn != true || channel?.isActive == true
			return true
		case .leaveChannel:
			item.isHidden = client?.isLoggedIn != true || channel?.isActive != true
			let joinHidden = item.menu?.item(for: .joinChannel)?.isHidden == true
			item.menu?.item(for: .leaveChannelSeparator)?.isHidden =
				item.isHidden && joinHidden
			return true
		case .addChannel:
			return client != nil
		case .viewChannelLogs:
			return TextualPreferences.logToDiskIsEnabled()
		case .modifyTopic, .modes, .bans:
			return client?.isLoggedIn == true && channel?.isActive == true
		case .banExceptions:
			item.isHidden = client?.supportInfo.isListSupported(.banException) != true
			return client?.isLoggedIn == true && channel?.isActive == true
		case .inviteExceptions:
			item.isHidden = client?.supportInfo.isListSupported(.inviteException) != true
			return client?.isLoggedIn == true && channel?.isActive == true
		case .quiets:
			item.isHidden = client?.supportInfo.isListSupported(.quiet) != true
			return client?.isLoggedIn == true && channel?.isActive == true
		default:
			return true
		}
	}

	private func validateWindowCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.command {
		case .toggleServerList, .sortChannelList,
		     .centerWindow, .resetWindow:
			return validateMainWindowCommand(item)
		case .mainWindow:
			item.isHidden = mainWindow.isMainWindow
			return mainWindow.isDisabled == false
		case .toggleMemberList:
			item.isHidden = mainWindow.isMainWindow == false
			item.title = MainWindowStrings.Menu.memberList(isVisible: mainWindow.isMemberListVisible)
			return channel?.isChannel == true && client?.isLoggedIn == true
		case .toggleAppearance:
			item.isHidden = mainWindow.isMainWindow == false
			item.menu?.item(for: .toggleAppearanceSeparator)?.isHidden = item.isHidden
			return true
		case .addressBook, .ignoreList:
			item.isHidden = mainWindow.isMainWindow == false
			return client != nil
		case .viewLogs:
			return TextualPreferences.logToDiskIsEnabled()
		case .highlightList:
			item.isHidden = mainWindow.isMainWindow == false
			return client != nil && TextualPreferences.logHighlights()
		default:
			return true
		}
	}

	private func validateWebCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.command {
		case .webChangeNickname:
			return client?.isConnected == true
		case .webSearch:
			guard let webView = selectedBackingView else { return false }
			item.title = ApplicationStrings.search(with: searchProviderName)
			return webView.hasSelection
		case .webDictionary:
			return validateDictionaryLookup(item)
		case .webCopy:
			return selectedBackingView?.hasSelection == true
		case .webPaste:
			return validatePaste()
		case .webQueryLogs:
			item.isHidden = channel?.isPrivateMessage != true
			return TextualPreferences.logToDiskIsEnabled()
		case .webChannelMenu:
			item.isHidden = channel?.isChannel != true
			let queryLogsHidden = item.menu?.item(for: .webQueryLogs)?.isHidden == true
			item.menu?.item(for: .webPasteSeparator)?.isHidden =
				item.isHidden && queryLogsHidden
			return true
		case .webReply, .webReact:
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

		switch item.command {
		case .addIgnore:
			return validateAddIgnore(item, client: client, channel: channel)
		case .modifyIgnore, .removeIgnore:
			return true
		case .inviteTo:
			guard let client, client.isLoggedIn, channel?.isUtility == false else { return false }
			return client.channelList.contains { $0 !== channel && $0.isChannel }
		case .whois, .ctcp:
			return client?.isLoggedIn == true && channel?.isUtility == false
		case .privateMessage:
			item.isHidden = channel?.isChannel != true
			return client?.isLoggedIn == true && channel?.isUtility == false
		case .changeColor:
			item.isHidden = channel?.isChannel != true
			return channel?.isChannel == true
		case .giveOp, .giveHalfop, .giveVoice,
		     .takeOp, .takeHalfop, .takeVoice:
			return client?.isLoggedIn == true && channel?.isActive == true
		case .allModesGiven:
			return false
		case .allModesTaken:
			return validateModeVisibility(item, client: client, channel: channel)
		case .ban, .kick, .kickban:
			let isChannel = channel?.isChannel == true
			item.isHidden = isChannel == false
			item.menu?.item(for: .kickbanSeparator)?.isHidden = isChannel == false
			return client?.isLoggedIn == true && isChannel && channel?.isActive == true
		case .ircOperator:
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

		switch item.command {
		case .toggleServerList:
			item.title = MainWindowStrings.Menu.serverList(isVisible: mainWindow.isServerListVisible)
		case .sortChannelList:
			item.menu?.item(for: .sortChannelListSeparator)?.isHidden = isMain == false
		case .resetWindow:
			item.menu?.item(for: .resetWindowSeparator)?.isHidden = isMain == false
		default:
			break
		}
		return true
	}

	private func validateAddIgnore(_ item: NSMenuItem, client: IRCClient?, channel: IRCChannel?) -> Bool {
		let modify = item.menu?.item(for: .modifyIgnore)
		let remove = item.menu?.item(for: .removeIgnore)

		guard channel?.isUtility == false else {
			modify?.isHidden = true
			remove?.isHidden = true
			item.isHidden = false
			return false
		}

		let members = selectedMembers(for: item)
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
		func hide(_ command: MenuCommand, _ hidden: Bool) {
			item.menu?.item(for: command)?.isHidden = hidden
		}

		guard channel?.isChannel == true else {
			for command in [
				MenuCommand.giveOp, .giveHalfop, .giveVoice,
				.takeOp, .takeHalfop, .takeVoice,
				.allModesGiven, .allModesGivenSeparator,
				.allModesTaken, .allModesTakenSeparator,
			] {
				hide(command, true)
			}
			return false
		}

		hide(.allModesGivenSeparator, false)
		hide(.allModesTakenSeparator, false)
		let members = selectedMembers(for: item)

		guard members.count == 1, let user = members.first else {
			for command in [
				MenuCommand.giveOp, .giveHalfop, .giveVoice,
				.takeOp, .takeHalfop, .takeVoice,
			] {
				hide(command, false)
			}
			hide(.allModesGiven, true)
			hide(.allModesTaken, true)
			return false
		}

		let hasOp = user.ranks.contains(.normalOperator)
		let hasVoice = user.ranks.contains(.voiced)
		let supportsHalfOp = client?.supportInfo.modeSymbolIsUserPrefix("h") == true
		let hasHalfOp = supportsHalfOp && user.ranks.contains(.halfOperator)

		hide(.giveOp, hasOp)
		hide(.takeOp, hasOp == false)
		hide(.giveVoice, hasVoice)
		hide(.takeVoice, hasVoice == false)
		hide(.giveHalfop, supportsHalfOp == false || hasHalfOp)
		hide(.takeHalfop, supportsHalfOp == false || hasHalfOp == false)
		hide(
			.allModesGiven,
			hasOp == false || hasVoice == false || (supportsHalfOp && hasHalfOp == false)
		)
		hide(.allModesTaken, hasOp || hasHalfOp || hasVoice)
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
