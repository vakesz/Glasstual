// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

private enum MenuServerSuppressionKey: String {
	case deleteChannel = "Delete Channel"
}

// MARK: - Server and channel commands

extension MenuActionController {
	@objc func connect(_: Any?) {
		connect(bypassingProxy: false)
	}

	@objc func connectBypassingProxy(_: Any?) {
		connect(bypassingProxy: true)
	}

	@objc func disconnect(_: Any?) {
		guard isRunning, let session = context.selectedSession,
		      MenuServerActionRules(session: session).canDisconnect
		else { return }
		session.quit()
	}

	@objc func cancelReconnection(_: Any?) {
		guard isRunning, let session = context.selectedSession,
		      MenuServerActionRules(session: session).canCancelReconnect
		else { return }
		session.cancelReconnect()
	}

	@objc func showServerChannelList(_: Any?) {
		guard isRunning, let session = context.selectedSession, session.isLoggedIn else { return }
		AppServices.serverChannelLists.openChannelList(for: session)
	}

	@objc func addServer(_: Any?) {
		guard isRunning else { return }
		MenuSheetPresenter.presentServerProperties(for: nil)
	}

	@objc func duplicateServer(_: Any?) {
		guard isRunning, let session = context.selectedSession, let chatSession else { return }

		let snapshot = session.config
		let identifier = UUID()
		serverDuplicationTasks[identifier] = Task { [weak self, weak session, weak chatSession] in
			var config = await KeychainSecretLoader.duplicate(snapshot)
			guard let self else { return }
			defer { serverDuplicationTasks[identifier] = nil }
			guard !Task.isCancelled, isRunning, let session, !session.isTerminating, let chatSession else { return }
			config.connectionName = MenuServerNamePolicy.duplicateName(of: config.connectionName)
			let newSession = chatSession.createSession(with: config)
			if newSession.config.sidebarItemExpanded {
				mainWindow.expandSession(newSession)
			}
			chatSession.save()
		}
	}

	@objc func deleteServer(_: Any?) {
		guard isRunning, let session = context.selectedSession,
		      let chatSession,
		      session.isConnecting == false,
		      session.isConnected == false
		else { return }
		let completion: AlertCompletion = { outcome in
			guard outcome.response == .default,
			      session.isConnecting == false,
			      session.isConnected == false
			else { return }
			chatSession.destroySession(session)
			chatSession.save()
		}
		/* Delete/Cancel, not Yes/No: the default button says what it does, which
		 is what makes a destructive confirmation readable at a glance. The
		 Return key still belongs to Cancel — see `AlertRequest`. */
		Alerts.alert(
			title: PromptStrings.Deletion.confirmationTitle(named: session.name),
			body: PromptStrings.Deletion.warning(for: .server),
			defaultButton: PromptStrings.Action.delete,
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default,
			completion: completion
		)
	}

	@objc func joinChannel(_: Any?) {
		guard isRunning, let session = context.selectedSession, let channel = context.selectedConversation,
		      session.canJoin(channel)
		else { return }
		session.join(channel)
		mainWindow.select(channel)
	}

	/// Channel ▸ Leave and Query ▸ Close are one command: a `#channel` is
	/// parted, anything else is closed.
	@objc func leaveConversation(_: Any?) {
		guard isRunning, let session = context.selectedSession, let conversation = context.selectedConversation,
		      conversation.associatedSession === session
		else { return }
		if conversation.isChannel {
			guard session.canJoinChannels, conversation.isActive else { return }
			session.part(conversation)
		} else {
			chatSession?.destroyConversation(conversation)
		}
	}

	@objc func addChannel(_: Any?) {
		guard isRunning, let session = context.selectedSession else { return }
		MenuSheetPresenter.presentChannelProperties(for: nil, on: session)
	}

	/// Removes the selected conversation for good. Only a `#channel` is worth
	/// confirming: anything else is closed without asking.
	@objc func deleteConversation(_: Any?) {
		guard isRunning, let conversation = context.selectedConversation, let chatSession else { return }
		if conversation.isChannel == false {
			chatSession.destroyConversation(conversation)
			chatSession.save()
			return
		}
		let completion: AlertCompletion = { outcome in
			guard outcome.response == .default else { return }
			chatSession.destroyConversation(conversation)
			chatSession.save()
		}
		Alerts.alert(
			title: PromptStrings.Deletion.confirmationTitle(named: conversation.name),
			body: PromptStrings.Deletion.warning(for: .channel),
			defaultButton: PromptStrings.Action.delete,
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default,
			suppressionKey: MenuServerSuppressionKey.deleteChannel.rawValue,
			completion: completion
		)
	}

	@objc func copyUniqueIdentifier(_: Any?) {
		guard let identifier = context.selectedConversation?.uniqueIdentifier else { return }
		NSPasteboard.general.stringContent = identifier
	}

	/// The transcript's channel-name menu, whose item carries the name.
	@objc func joinChannelClicked(_ sender: NSMenuItem?) {
		guard let channelName = sender?.userInfoString else { return }
		joinChannel(named: channelName)
	}

	/// A channel name the reader activated in the transcript, which carries no
	/// menu item of its own.
	func joinChannel(named channelName: String) {
		guard isRunning, let session = context.selectedSession, session.canJoinChannels,
		      session.stringIsChannelName(channelName),
		      let channel = session.findConversationOrCreate(channelName)
		else { return }
		session.join(channel)
		mainWindow.select(channel)
	}

	/// Nothing may act on the sidebar once the application has begun shutting
	/// down.
	private var isRunning: Bool {
		AppServices.delegate.applicationIsTerminating == false
	}

	private func connect(bypassingProxy: Bool) {
		guard isRunning, let session = context.selectedSession else { return }
		let policy = MenuServerActionRules(session: session)
		guard bypassingProxy ? policy.canConnectWithoutProxy : policy.canConnect else { return }
		if bypassingProxy {
			session.connect(.normal, bypassProxy: true)
		} else {
			session.connect()
		}
		mainWindow.expandSession(session)
	}

	// MARK: - Channel mode commands

	@objc func showChannelMaskList(_: Any?) {
		showModeList(maskKind: .ban, symbol: "+b")
	}

	@objc func showChannelBanExceptionList(_: Any?) {
		showModeList(maskKind: .banException, symbol: "+e")
	}

	@objc func showChannelInviteExceptionList(_: Any?) {
		showModeList(maskKind: .inviteException, symbol: "+I")
	}

	@objc func showChannelQuietList(_: Any?) {
		showModeList(maskKind: .quiet, symbol: "+q")
	}

	/// One ticked item per mode, so the command says which way it is about to
	/// go. It used to be two items — "Moderated" and "Unmoderated" — neither of
	/// which showed which one was in force.
	@objc func toggleChannelModerationMode(_: Any?) {
		sendMode("m", set: context.channelModeIsSet("m") == false)
	}

	@objc func toggleChannelInviteMode(_: Any?) {
		sendMode("i", set: context.channelModeIsSet("i") == false)
	}

	private func showModeList(maskKind: ChannelMaskKind, symbol: String) {
		guard let session = context.selectedSession, let channel = context.selectedConversation,
		      session.isLoggedIn, channel.isChannel
		else { return }
		AppServices.channelMaskList.open(maskKind: maskKind, in: channel)
		session.sendModes(symbol, withParametersString: nil, inChannelNamed: channel.name)
	}

	private func sendMode(_ symbol: String, set: Bool) {
		guard isRunning, let session = context.selectedSession, let channel = context.selectedConversation,
		      ChannelActionPermissions(channel: channel, session: session).canChangeModes
		else { return }
		session.sendModes("\(set ? "+" : "-")\(symbol)", withParametersString: nil, inChannelNamed: channel.name)
	}
}
