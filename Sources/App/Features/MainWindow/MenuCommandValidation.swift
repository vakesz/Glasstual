/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
import GlasstualPluginKit

private enum MenuValidationConstants {
	static let maximumDictionaryLookupLength = 40
	static let maximumDictionaryMenuTitleLength = 25
	static let truncatedDictionaryMenuTitleLength = 24
}

/// Which web-search service the system is set to use, which is what the
/// transcript's Search command has to name. The menu is built with it and
/// validation refreshes it, so the item never says "Google" to someone whose
/// system is set to DuckDuckGo.
@MainActor
public enum MenuSearchProvider {
	private static let preferredWebServicesKey = "NSPreferredWebServices"
	private static let webSearchProviderKey = "NSWebServicesProviderWebSearch"
	private static let defaultDisplayNameKey = "NSDefaultDisplayName"
	private static let fallbackName = "Google"

	public static var name: String {
		let services = UserDefaults.standard.dictionary(forKey: preferredWebServicesKey)
		let provider = services?[webSearchProviderKey]
			.flatMap(PropertyListValue.init(propertyList:))

		return provider?.dictionary?[defaultDisplayNameKey]?.string ?? fallbackName
	}

	public static var menuTitle: String {
		ApplicationStrings.search(with: name)
	}
}

/// Where a Paste command puts what it is carrying.
public nonisolated enum MenuPasteTarget: Sendable { // nonisolated: value
	/// Whatever holds the keyboard.
	case firstResponder
	/// The chat input, which is where the main window sends a paste that has no
	/// editable responder of its own to go to.
	case inputField
	/// Nowhere: nothing editable holds the keyboard and there is no input field.
	case none
}

/** The two menu rules that were asking the wrong thing.

 Paste asked whether the main window was key and then validated against the
 chat input, so it read as enabled while the caret was in the toolbar's search
 field or a sheet's field. Change Nickname asked whether the client was
 connected while the action it enables guards on being logged in -- and closes
 the presented sheet on the way -- so choosing it dismissed an unrelated sheet
 and then did nothing. */
@MainActor
public enum MenuResponderCommandPolicy {
	/** Paste is a property of the responder that will receive it.

	 The menu item and the action ask the same question of the same three
	 inputs: the item was enabled only for an editable responder while the
	 action fell back to the message field, so ⌘V read as unavailable while the
	 reader was in the transcript -- and the shortcut, which AppKit validates
	 through the item, did nothing at all. */
	public static func canPaste(
		pasteboardHasText: Bool,
		responderIsEditableText: Bool,
		responderIsInInputBar: Bool,
		hasInputField: Bool
	) -> Bool {
		guard pasteboardHasText else { return false }
		return pasteTarget(
			responderIsEditableText: responderIsEditableText,
			responderIsInInputBar: responderIsInInputBar,
			hasInputField: hasInputField
		) != .none
	}

	/** Which of the two the paste is aimed at.

	 The same question ``canPaste(pasteboardHasText:responderIsEditableText:responderIsInInputBar:hasInputField:)``
	 answers, asked for the action rather than the menu item: the responder holding
	 the keyboard is the destination, and the chat input is only a fallback. Sending
	 every paste to the input field pulled the focus out of the toolbar's search
	 field or a sheet's field and dropped the text into the conversation
	 instead, so the field is chosen only when the responder belongs to the
	 input bar already, or when nothing editable has the keyboard at all. */
	public static func pasteTarget(
		responderIsEditableText: Bool,
		responderIsInInputBar: Bool,
		hasInputField: Bool
	) -> MenuPasteTarget {
		if responderIsEditableText, responderIsInInputBar == false {
			return .firstResponder
		}
		if hasInputField {
			return .inputField
		}
		return responderIsEditableText ? .firstResponder : .none
	}

	/// Change Nickname needs a registered connection, not merely a socket.
	public static func canChangeNickname(clientIsLoggedIn: Bool) -> Bool {
		clientIsLoggedIn
	}
}

/** Menu validation.

 Availability is enablement, not visibility: a command the selection cannot
 carry out is dimmed where it always sits, so the menus keep their shape and
 stay learnable. The one exception is a pair of commands that are two states of
 the same thing — Connect and Disconnect, Join and Leave — where showing both
 would offer a choice that does not exist. */
@MainActor
extension MenuActionCoordinator {
	/// AppKit asks the item's target, which is this object: the menu controller
	/// is the menus' delegate, and a delegate is not consulted about
	/// enablement.
	public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		let appController: ApplicationController = AppController.shared
		guard appController.applicationIsTerminating == false else { return false }

		return MenuValidationPolicy.validate(
			command: menuItem.command,
			commandSpecificResult: validateCommand(menuItem),
			applicationIsLaunched: appController.applicationIsLaunched,
			mainWindowHasAttachedSheet: mainWindow.attachedSheet != nil,
			mainWindowIsFocused: mainWindow.isMainWindow,
			hasExplicitMenuContext: hasExplicitMenuContext
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
		switch item.command {
		case .closeWindow:
			return validateCloseWindow(item)
		case .paste:
			return validatePaste()
		case .markScrollback, .scrollbackMarker,
		     .markAllRead, .clearScrollback,
		     .increaseFont, .decreaseFont, .actualSize,
		     .jumpToCurrentSession, .jumpToPresent:
			return selectedViewController != nil
		case .nextHighlight, .previousHighlight:
			return selectedViewController?.hasHighlightedLines == true
		case .segmentedAddChannel:
			return selectedClient != nil
		case .queryLogs:
			return selectedChannel?.isPrivateMessage == true && TextualPreferences.logToDiskIsEnabled()
		case .developerMode:
			item.state = Preferences.Commands.developerMode.value ? .on : .off
			return true
		case .muteNotifications, .dockMuteNotifications:
			/* A mode is ticked while it is in force. The item used to be
			 renamed instead, so the menu read as a command and its two homes
			 disagreed about what to call it. */
			item.state = SharedApplication.sharedNotificationController().areNotificationsDisabled ? .on : .off
			return true
		case .muteNotificationSounds, .dockMuteNotificationSounds:
			item.state = Preferences.Notifications.soundIsMuted.value ? .on : .off
			return true
		default:
			return true
		}
	}

	func validateServerCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let policy = MenuServerActionPolicy(client: client)
		/* Connect and Disconnect are one command in two states, so only the one
		 that applies is shown; the proxy-free variant is Connect's Option
		 alternate and follows it. */
		let isConnected = client.map { $0.isConnected || $0.isConnecting } == true

		switch item.command {
		case .connect, .connectWithoutProxy:
			item.isHidden = isConnected
			return item.command == .connect ? policy.canConnect : policy.canConnectWithoutProxy
		case .disconnect:
			item.isHidden = isConnected == false
			return policy.canDisconnect
		case .cancelReconnect:
			return policy.canCancelReconnect
		case .channelList:
			return client?.isLoggedIn == true
		case .changeNickname:
			/* The action guards on `isLoggedIn`, and it closes the presented
			 sheet before it gets there: validating on the looser `isConnected`
			 offered a command that dismissed an unrelated sheet and then did
			 nothing. */
			return MenuResponderCommandPolicy.canChangeNickname(clientIsLoggedIn: client?.isLoggedIn == true)
		case .duplicateServer, .addChannelToServer, .serverProperties:
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
		/* The mirror of `IRCClient.canJoin`, for a channel that is already
		 joined: the same connection, the same channel list, and a channel the
		 client has not finished with. */
		let isJoined = channel.map { channel in
			client?.canJoinChannels == true
				&& channel.associatedClient === client
				&& client?.channelList.contains(where: { $0 === channel }) == true
				&& channel.isChannel && channel.isActive
		} == true

		switch item.command {
		case .joinChannel:
			item.isHidden = isJoined
			return channel.map { client?.canJoin($0) == true } == true
		case .leaveChannel:
			item.isHidden = isJoined == false
			return isJoined
		case .addChannel:
			return client != nil
		case .viewChannelLogs:
			return channel != nil && TextualPreferences.logToDiskIsEnabled()
		case .modifyTopic, .modes, .channelModeManageAll, .bans:
			return isJoined
		case .channelModeModerated:
			item.state = channelModeIsSet("m") ? .on : .off
			return isJoined
		case .channelModeInviteOnly:
			item.state = channelModeIsSet("i") ? .on : .off
			return isJoined
		case .banExceptions:
			return isJoined && client?.supportInfo.isListSupported(.banException) == true
		case .inviteExceptions:
			return isJoined && client?.supportInfo.isListSupported(.inviteException) == true
		case .quiets:
			return isJoined && client?.supportInfo.isListSupported(.quiet) == true
		case .channelProperties:
			return channel?.isChannel == true
		case .copyChannelIdentifier:
			return channel != nil
		default:
			return true
		}
	}

	private func validateWindowCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.command {
		case .toggleServerList:
			item.title = MainWindowStrings.Menu.serverList(isVisible: mainWindow.isServerListVisible)
			return mainWindow.isMainWindow
		case .toggleMemberList:
			item.title = MainWindowStrings.Menu.memberList(isVisible: mainWindow.isMemberListVisible)
			return mainWindow.isMainWindow && channel?.isChannel == true && client?.isLoggedIn == true
		case .appearanceSystem, .appearanceLight, .appearanceDark:
			let appearance = MenuWindowPolicy.appearance(for: item.command)
			item.state = appearance == Preferences.Appearance.preferredAppearance.value ? .on : .off
			return true
		case .sortChannelList, .centerWindow, .resetWindow:
			return mainWindow.isMainWindow
		case .addressBook:
			return client != nil
		case .viewLogs:
			return TextualPreferences.logToDiskIsEnabled()
		case .highlightList:
			return client != nil && Preferences.Logging.logHighlights.value
		default:
			return true
		}
	}

	private func validateWebCommand(_ item: NSMenuItem) -> Bool {
		let client = selectedClient
		let channel = selectedChannel

		switch item.command {
		case .webChangeNickname:
			/* The same command from the transcript's menu, so the same guard. */
			return MenuResponderCommandPolicy.canChangeNickname(clientIsLoggedIn: client?.isLoggedIn == true)
		case .webSearch:
			item.title = MenuSearchProvider.menuTitle
			return selectedBackingView?.hasSelection == true
		case .webDictionary:
			return validateDictionaryLookup(item)
		case .webPaste:
			return validatePaste()
		case .webQueryLogs:
			return channel?.isPrivateMessage == true && TextualPreferences.logToDiskIsEnabled()
		case .webChannelMenu:
			return channel?.isChannel == true
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
			return existingIgnore(for: item) == .none
		case .modifyIgnore, .removeIgnore:
			return existingIgnore(for: item) == .some
		case .inviteTo:
			guard let client, client.isLoggedIn, channel?.isUtility == false else { return false }
			return client.channelList.contains { $0 !== channel && $0.isChannel }
		case .whois, .ctcp, .ctcpSendFile, .ctcpPing, .ctcpTime,
		     .ctcpClientInfo, .ctcpVersion, .ctcpFinger, .ctcpUserInfo:
			return client?.isLoggedIn == true && channel?.isUtility == false
		case .privateMessage:
			return client?.isLoggedIn == true && channel?.isChannel == true
		case .changeColor:
			return channel?.isChannel == true
		case .giveOp, .giveHalfop, .giveVoice, .takeOp, .takeHalfop, .takeVoice:
			return validateMemberMode(item, client: client, channel: channel)
		case .ban, .kick, .kickban:
			return client?.isLoggedIn == true && channel?.isChannel == true && channel?.isActive == true
		case .ircOperator, .operatorSetVirtualHost, .operatorKill, .operatorShun, .operatorGline:
			return client?.userIsIRCop == true && client?.isLoggedIn == true && channel?.isUtility == false
		default:
			return true
		}
	}

	/// Whether the clicked member already has an ignore entry. `nil` where the
	/// question does not apply — no single member, no hostmask, no connection —
	/// which disables all three ignore commands.
	private enum MemberIgnoreState {
		case none
		case some
		case unknown
	}

	private func existingIgnore(for item: NSMenuItem) -> MemberIgnoreState {
		guard selectedChannel?.isUtility == false,
		      let client = selectedClient
		else { return .unknown }

		let members = selectedMembers(for: item)
		guard members.count == 1, let hostmask = members.first?.user.hostmask else {
			return .unknown
		}

		return client.findIgnores(forHostmask: hostmask).isEmpty ? .none : .some
	}

	/// A rank command applies when the member does not already stand where it
	/// would put them, and the server knows the rank at all.
	private func validateMemberMode(_ item: NSMenuItem, client: IRCClient?, channel: Channel?) -> Bool {
		guard client?.isLoggedIn == true, channel?.isChannel == true, channel?.isActive == true else {
			return false
		}

		let members = selectedMembers(for: item)
		let supportsHalfOp = client?.supportInfo.modeSymbolIsUserPrefix("h") == true

		guard members.count == 1, let user = members.first else {
			/* A multiple selection has no single rank to compare against, so
			 every rank command applies to it. */
			return members.isEmpty == false
				&& (supportsHalfOp || (item.command != .giveHalfop && item.command != .takeHalfop))
		}

		let hasOp = user.ranks.contains(.normalOperator)
		let hasVoice = user.ranks.contains(.voiced)
		let hasHalfOp = supportsHalfOp && user.ranks.contains(.halfOperator)

		return switch item.command {
		case .giveOp: hasOp == false
		case .takeOp: hasOp
		case .giveVoice: hasVoice == false
		case .takeVoice: hasVoice
		case .giveHalfop: supportsHalfOp && hasHalfOp == false
		case .takeHalfop: supportsHalfOp && hasHalfOp
		default: false
		}
	}

	/** Paste applies to whatever holds the keyboard.

	 It used to validate against the chat input whenever the main window was
	 key, so Paste read as enabled while the caret sat in the toolbar's search
	 field or a sheet's field -- and then pasted into the wrong one. The
	 responder is the answer in both branches, and the branches are the same
	 ones ``MenuActionCoordinator/paste(_:)`` takes: the item has to be enabled
	 wherever the action has somewhere to put the text. */
	private func validatePaste() -> Bool {
		let responder = NSApp.keyWindow?.firstResponder
		return MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: NSPasteboard.general.string(forType: .string)?.isEmpty == false,
			responderIsEditableText: (responder as? NSText)?.isEditable == true,
			responderIsInInputBar: responderBelongsToInputBar(responder),
			hasInputField: mainWindow.isKeyWindow ? mainWindow.inputTextField != nil : false
		)
	}

	private func validateCloseWindow(_ item: NSMenuItem) -> Bool {
		let action = Preferences.Input.commandWKeyAction.value
		if action == .closeWindow || mainWindow.isKeyWindow == false {
			item.title = ApplicationStrings.closeWindow
			return true
		}
		guard let client = selectedClient else {
			item.title = ApplicationStrings.closeWindow
			return false
		}

		switch action {
		case .partChannel:
			guard let channel = selectedChannel else {
				item.title = ApplicationStrings.closeWindow
				return false
			}
			item.title = channel.isChannel ? ApplicationStrings.leaveChannel : ApplicationStrings.closeQuery
			return channel.isChannel == false || channel.isActive
		case .disconnect:
			item.title = ApplicationStrings.disconnect(from: client.networkNameAlt)
			return MenuServerActionPolicy(client: client).canDisconnect
		case .terminate:
			item.title = ApplicationStrings.quitApplication
			return true
		default:
			return true
		}
	}

	private func validateDictionaryLookup(_ item: NSMenuItem) -> Bool {
		guard let selection = selectedBackingView?.selection else { return false }
		let length = selection.count
		guard length > 0, length <= MenuValidationConstants.maximumDictionaryLookupLength else {
			item.title = ApplicationStrings.lookUpInDictionary
			return false
		}

		let truncatedSelection = selection
			.prefix(MenuValidationConstants.truncatedDictionaryMenuTitleLength)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let titleSelection = length > MenuValidationConstants.maximumDictionaryMenuTitleLength
			? "\(truncatedSelection)…"
			: selection
		item.title = ApplicationStrings.lookUpInDictionary(titleSelection)
		return true
	}
}
