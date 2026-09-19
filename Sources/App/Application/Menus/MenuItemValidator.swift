// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

private enum MenuValidationConstants {
	static let maximumDictionaryLookupLength = 40
	static let maximumDictionaryMenuTitleLength = 25
	static let truncatedDictionaryMenuTitleLength = 24
}

/** Whether a menu command may be chosen.

 Availability is enablement, not visibility: a command the selection cannot
 carry out is dimmed where it always sits, so the menus keep their shape and
 stay learnable. The one exception is a pair of commands that are two states of
 the same thing — Connect and Disconnect, Join and Leave — where showing both
 would offer a choice that does not exist.

 It reads the same ``MenuContextResolver`` the commands do, which is what makes
 an item's enablement and its action answer the same question. Some commands
 also settle their item's title or tick here: what a command says and whether it
 applies are one decision. */
@MainActor
struct MenuItemValidator {
	let context: MenuContextResolver

	private var mainWindow: MainWindow {
		context.mainWindow
	}

	/// What the command would act on, which is what almost every group below
	/// asks about.
	private var session: ServerSession? {
		context.selectedSession
	}

	private var conversation: Conversation? {
		context.selectedConversation
	}

	func validate(_ menuItem: NSMenuItem) -> Bool {
		let appController: ApplicationDelegate = AppServices.delegate
		guard appController.applicationIsTerminating == false else { return false }

		return Self.isAvailable(
			command: menuItem.command,
			commandSpecificResult: validateCommand(menuItem),
			applicationIsLaunched: appController.applicationIsLaunched,
			mainWindowHasAttachedSheet: mainWindow.attachedSheet != nil,
			mainWindowIsFocused: mainWindow.isMainWindow,
			hasExplicitMenuContext: context.hasExplicitMenuContext
		)
	}

	/** Whether the command is available at all, given what has the keyboard.

	 The pointer used to be part of this: a command was live while the main
	 window merely sat under the mouse, so what a menu offered depended on where
	 the pointer happened to be rather than on what was focused. */
	static func isAvailable(
		command: MenuCommand?,
		commandSpecificResult: Bool,
		applicationIsLaunched: Bool,
		mainWindowHasAttachedSheet: Bool,
		mainWindowIsFocused: Bool,
		hasExplicitMenuContext: Bool
	) -> Bool {
		guard commandSpecificResult else {
			return false
		}

		if command?.isTopLevelMenu == true {
			return true
		}

		/* A contextual menu names the row it was opened on, which answers for
		 the main window whether or not the window is focused. */
		let mainWindowIsAnswering = mainWindowHasAttachedSheet == false
			&& (mainWindowIsFocused || hasExplicitMenuContext)

		if applicationIsLaunched, mainWindowIsAnswering {
			return true
		}

		if mainWindowIsAnswering == false, command?.isAvailableDuringSheets == true {
			return true
		}

		return command?.isEssential == true
	}

	private func validateCommand(_ item: NSMenuItem) -> Bool {
		switch item.command?.validationGroup {
		case .server:
			validateServerCommand(item)
		case .channel:
			validateChannelCommand(item)
		case .window:
			validateWindowCommand(item)
		case .transcript:
			validateTranscriptCommand(item)
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
		case .setUnreadMarker, .gotoUnreadMarker,
		     .markAllRead, .clearScrollback,
		     .increaseFont, .decreaseFont, .actualSize,
		     .jumpToCurrentSession, .jumpToPresent:
			return context.selectedViewController != nil
		case .nextHighlight, .previousHighlight:
			return context.selectedViewController?.hasHighlightedLines == true
		case .queryLogs:
			/* The Query menu's item and the transcript menu's are the same
			 command, so one guard answers for both. */
			return conversation?.isDirect == true && ApplicationPaths.isWritingTranscripts
		case .developerMode:
			item.state = SettingsKeys.Commands.developerMode.value ? .on : .off
			return true
		case .muteNotifications:
			/* A mode is ticked while it is in force. The item used to be
			 renamed instead, so the menu read as a command and its two homes
			 disagreed about what to call it. */
			item.state = AppServices.notifications.areNotificationsDisabled ? .on : .off
			return true
		case .muteNotificationSounds:
			item.state = SettingsKeys.Notifications.soundIsMuted.value ? .on : .off
			return true
		default:
			return true
		}
	}

	func validateServerCommand(_ item: NSMenuItem) -> Bool {
		let policy = MenuServerActionRules(session: session)
		/* Connect and Disconnect are one command in two states, so only the one
		 that applies is shown; the proxy-free variant is Connect's Option
		 alternate and follows it. */
		let isConnected = session.map { $0.isConnected || $0.isConnecting } == true

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
			return session?.isLoggedIn == true
		case .changeNickname:
			/* The action guards on `isLoggedIn`. Validating on the looser
			 `isConnected` offered a command that did nothing during
			 registration. The transcript's menu offers the same command, so it
			 reaches this guard too. */
			return session?.isLoggedIn == true
		case .duplicateServer, .serverProperties:
			return session != nil
		case .deleteServer:
			return session.map { $0.isConnecting == false && $0.isConnected == false } == true
		default:
			return true
		}
	}

	private func validateChannelCommand(_ item: NSMenuItem) -> Bool {
		/* The mirror of `ServerSession.canJoin`, for a channel that is already
		 joined: the same connection, the same conversation list, and a channel
		 the session has not finished with. */
		let isJoined = conversation.map { candidate in
			session?.canJoinChannels == true
				&& candidate.associatedSession === session
				&& session?.conversationList.contains(where: { $0 === candidate }) == true
				&& candidate.isChannel && candidate.isActive
		} == true

		switch item.command {
		case .joinChannel:
			item.isHidden = isJoined
			return conversation.map { session?.canJoin($0) == true } == true
		case .leaveChannel:
			item.isHidden = isJoined == false
			return isJoined
		case .addChannel:
			return session != nil
		case .viewChannelLogs:
			return conversation != nil && ApplicationPaths.isWritingTranscripts
		case .modifyTopic, .modes, .channelModeManageAll, .bans:
			return isJoined
		case .channelModeModerated:
			item.state = context.channelModeIsSet("m") ? .on : .off
			return isJoined
		case .channelModeInviteOnly:
			item.state = context.channelModeIsSet("i") ? .on : .off
			return isJoined
		case .banExceptions:
			return isJoined && session?.supportInfo.isListSupported(.banException) == true
		case .inviteExceptions:
			return isJoined && session?.supportInfo.isListSupported(.inviteException) == true
		case .quiets:
			return isJoined && session?.supportInfo.isListSupported(.quiet) == true
		case .channelProperties:
			return conversation?.isChannel == true
		case .copyChannelIdentifier:
			return conversation != nil
		default:
			return true
		}
	}

	private func validateWindowCommand(_ item: NSMenuItem) -> Bool {
		switch item.command {
		case .toggleSidebar:
			item.title = MenuCommand.sidebarTitle(isVisible: mainWindow.columnModel.isSidebarVisible)
			return mainWindow.isMainWindow
		case .toggleMemberList:
			item.title = MenuCommand.memberListTitle(isVisible: mainWindow.columnModel.isMemberListVisible)
			return mainWindow.isMainWindow && conversation?.isChannel == true && session?.isLoggedIn == true
		case .appearanceSystem, .appearanceLight, .appearanceDark:
			let appearance = MenuWindowPolicy.appearance(for: item.command)
			item.state = appearance == SettingsKeys.Appearance.preferredAppearance.value ? .on : .off
			return true
		case .sortChannelList, .centerWindow, .resetWindow:
			return mainWindow.isMainWindow
		case .addressBook:
			return session != nil
		case .viewLogs:
			return ApplicationPaths.isWritingTranscripts
		case .highlightList:
			return session != nil && SettingsKeys.Logging.logHighlights.value
		default:
			return true
		}
	}

	private func validateTranscriptCommand(_ item: NSMenuItem) -> Bool {
		switch item.command {
		case .webSearch:
			item.title = SystemWebSearch.menuTitle
			return context.selectedBackingView?.hasSelection == true
		case .transcriptDictionary:
			return validateDictionaryLookup(item)
		case .transcriptChannelMenu:
			return conversation?.isChannel == true
		case .transcriptReply, .transcriptReact:
			return session != nil
				&& conversation?.isConsole == false
				&& session?.isCapabilityEnabled(.messageTags) == true
		default:
			return true
		}
	}

	private func validateMemberCommand(_ item: NSMenuItem) -> Bool {
		switch item.command {
		case .addIgnore:
			return existingIgnore(for: item) == .none
		case .modifyIgnore, .removeIgnore:
			return existingIgnore(for: item) == .some
		case .inviteTo:
			guard let session, session.isLoggedIn, conversation?.isConsole == false else { return false }
			return session.conversationList.contains { $0 !== conversation && $0.isChannel }
		case .whois, .ctcp, .ctcpSendFile, .ctcpPing, .ctcpTime,
		     .ctcpClientInfo, .ctcpVersion, .ctcpFinger, .ctcpUserInfo:
			return session?.isLoggedIn == true && conversation?.isConsole == false
		case .startDirectConversation:
			return session?.isLoggedIn == true && conversation?.isChannel == true
		case .changeColor:
			return conversation?.isChannel == true
		case .giveOp, .giveHalfop, .giveVoice, .takeOp, .takeHalfop, .takeVoice:
			return validateMemberMode(item)
		case .ban, .kick, .kickban:
			return session?.isLoggedIn == true && conversation?.isChannel == true && conversation?.isActive == true
		case .ircOperator, .operatorSetVirtualHost, .operatorKill, .operatorShun, .operatorGline:
			return session?.userIsIRCop == true && session?.isLoggedIn == true && conversation?.isConsole == false
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
		guard conversation?.isConsole == false, let session else { return .unknown }

		let members = context.selectedMembers(for: item)
		guard members.count == 1, let hostmask = members.first?.user.hostmask else {
			return .unknown
		}

		return session.findIgnores(forHostmask: hostmask).isEmpty ? .none : .some
	}

	/// A rank command applies when the member does not already stand where it
	/// would put them, and the server knows the rank at all.
	private func validateMemberMode(_ item: NSMenuItem) -> Bool {
		guard session?.isLoggedIn == true, conversation?.isChannel == true, conversation?.isActive == true else {
			return false
		}

		let members = context.selectedMembers(for: item)
		let supportsHalfOp = session?.supportInfo.modeSymbolIsUserPrefix("h") == true

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
	 ones ``MenuActionController/paste(_:)`` takes: the item has to be enabled
	 wherever the action has somewhere to put the text. */
	private func validatePaste() -> Bool {
		let responder = NSApp.keyWindow?.firstResponder
		return MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: NSPasteboard.general.string(forType: .string)?.isEmpty == false,
			responderIsEditableText: (responder as? NSText)?.isEditable == true,
			responderIsInInputBar: context.responderBelongsToInputBar(responder),
			hasInputField: mainWindow.isKeyWindow ? mainWindow.inputTextField != nil : false
		)
	}

	private func validateCloseWindow(_ item: NSMenuItem) -> Bool {
		let action = SettingsKeys.Input.commandWKeyAction.value
		if action == .closeWindow || mainWindow.isKeyWindow == false {
			item.title = ApplicationStrings.closeWindow
			return true
		}
		guard let session else {
			item.title = ApplicationStrings.closeWindow
			return false
		}

		switch action {
		case .closeConversation:
			guard let conversation else {
				item.title = ApplicationStrings.closeWindow
				return false
			}
			item.title = conversation.isChannel ? ApplicationStrings.leaveChannel : ApplicationStrings.closeQuery
			return conversation.isChannel == false || conversation.isActive
		case .disconnect:
			item.title = ApplicationStrings.disconnect(from: session.networkNameAlt)
			return MenuServerActionRules(session: session).canDisconnect
		case .terminate:
			item.title = ApplicationStrings.quitApplication
			return true
		default:
			return true
		}
	}

	private func validateDictionaryLookup(_ item: NSMenuItem) -> Bool {
		guard let selection = context.selectedBackingView?.selection else { return false }
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
