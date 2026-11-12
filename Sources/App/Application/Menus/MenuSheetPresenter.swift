// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The sheets a menu command raises, and what each one does with what it was
 given.

 Every entry point takes what it acts on rather than reading the selection: the
 command decides whether it can act -- see the ordering below -- and this puts
 the sheet on screen. A sheet reports what the person accepted through a closure
 it was built with, so the command and its answer are written together.

 The window is read for each sheet rather than held, because the menus exist
 before the main window does. */
@MainActor
enum MenuSheetPresenter {
	/** The launch sequence every sheet command shares.

	 The sheet already on screen comes down first, and only then is the new one
	 built and attached to the window. Each command checks it can act before it
	 gets here: the other order dismissed an unrelated sheet, and the edits in
	 it, for a command that then did nothing. `start` is the sheet's own entry
	 point, because each one opens with what it needs rather than with a shared
	 signature. */
	private static func present<Sheet: SheetSession>(
		_ make: @autoclosure () -> Sheet,
		start: (Sheet) -> Void
	) {
		guard let window = AppServices.delegate?.mainWindow else { return }
		window.sheetModel.dismissPresentedSheet()
		let sheet = make()
		sheet.window = window
		start(sheet)
	}

	private static var window: MainWindow? {
		AppServices.delegate?.mainWindow
	}

	/** Opens `request` as a command in the message field, when the reader chose
	 the conversation and there is a conversation to type it in. `false` leaves
	 the caller to open the sheet. */
	private static func opensAsCommand(_ request: EditorRequest) -> Bool {
		guard let window, window.selectedItem != nil,
		      case let .prefill(command, selection) = EditorRouting.route(request, style: SettingsKeys.Interaction.style.value)
		else { return false }
		window.prefillInput(command, selecting: selection)
		return true
	}

	/** Opens the connection sheet, on an existing connection or on a new one.

	 A new connection is created once the sheet is accepted; an existing one is
	 updated in place, and the transcript is redrawn only where the encoding
	 changed, because that is what decides how the lines already on screen are
	 decoded. */
	static func presentServerProperties(
		for session: ServerSession?,
		at destination: ServerPropertiesDestination = .default
	) {
		if session == nil, case .default = destination, opensAsCommand(.newServer) {
			return
		}
		if let session, opensServerPropertiesAsCommand(for: session, at: destination) {
			return
		}
		present(ServerPropertiesSheet(session: session) { [weak session] config in
			guard let directory = AppServices.chatSession else { return }
			guard let session else {
				let created = directory.createSession(with: config)
				window?.expandSession(created)
				directory.save()
				return
			}
			applyServerConfiguration(config, to: session)
		}) { $0.start(at: destination) }
	}

	/// The conversation's way into the connection sheet: `/serverconfig`, or
	/// `/ignore` for the address book.
	private static func opensServerPropertiesAsCommand(
		for _: ServerSession,
		at destination: ServerPropertiesDestination
	) -> Bool {
		switch destination {
		case .default:
			opensAsCommand(.serverProperties)
		case let .newIgnoreEntry(hostmask):
			opensAsCommand(.ignore(mask: hostmask?.isEmpty == false ? hostmask : nil))
		case .addressBook:
			opensAsCommand(.ignore(mask: nil))
		case let .editIgnoreEntry(entry):
			opensAsCommand(.ignore(mask: entry.hostmask))
		}
	}

	/** Saves an edited connection the way the sheet does: the transcript is
	 redrawn only where the encoding changed, because that is what decides how
	 the lines already on screen are decoded. `/serverconfig` saves through here
	 too. */
	static func applyServerConfiguration(_ config: ServerConfig, to session: ServerSession) {
		let encodingChanged = config.primaryEncoding != session.config.primaryEncoding
		session.updateConfig(config)
		if encodingChanged {
			window?.reloadTheme()
		}
		window?.reloadChatItemGroup(session)
		session.chatSession?.save()
	}

	/// Saves an edited channel the way the sheet does; `/channelconfig` too.
	static func applyChannelConfiguration(_ config: ConversationConfig, to channel: Conversation) {
		channel.updateConfig(config)
		channel.associatedSession?.chatSession?.save()
	}

	/// Redraws whatever draws nicknames after a pinned colour changed.
	static func nicknameColorsChanged() {
		window?.reloadTheme()
		/* The transcript is redrawn by the theme reload; the member list's
		 avatars take their pinned colours from a snapshot the list reads
		 when its presentation is invalidated, and nothing else invalidates
		 it here. */
		window?.memberList.invalidatePresentation()
	}

	/// Opens the channel sheet, on an existing channel or on a new one for
	/// `session`. Adding a channel in the conversation style puts `/join` in
	/// the message field instead.
	static func presentChannelProperties(for channel: Conversation?, on session: ServerSession?) {
		if channel == nil, session != nil, opensAsCommand(.addChannel) {
			return
		}
		let save: (ConversationConfig) -> Void = { [weak session, weak channel] config in
			guard let directory = AppServices.chatSession, let session else { return }
			guard let channel else {
				directory.addConversation(with: config, on: session)
				window?.expandSession(session)
				return
			}
			applyChannelConfiguration(config, to: channel)
		}
		if let channel, opensAsCommand(.channelProperties(channel: channel.name)) {
			return
		}
		present(channel.map { ChannelPropertiesSheet(channel: $0, onSave: save) }
			?? ChannelPropertiesSheet(
				config: nil,
				onSession: session,
				siblingNames: ChannelPropertiesSheet.siblingNames(
					in: session?.config.conversationList ?? [],
					excluding: nil
				),
				onSave: save
			)) { $0.startSheet() }
	}

	static func presentChannelTopic(for channel: Conversation) {
		guard ChannelActionPermissions(channel: channel, session: channel.associatedSession).canModifyTopic else { return }
		if opensAsCommand(.topic(channel: channel.name, current: channel.topic ?? "")) {
			return
		}
		present(ChannelTopicSheet(channel: channel) { [weak channel] topic in
			guard let channel, let session = channel.associatedSession,
			      ChannelActionPermissions(channel: channel, session: session).canModifyTopic
			else { return }
			session.sendTopic(to: topic, in: channel)
		}) { $0.startSheet() }
	}

	static func presentChannelModes(for channel: Conversation) {
		guard ChannelActionPermissions(channel: channel, session: channel.associatedSession).canChangeModes else { return }
		if opensAsCommand(.modes(channel: channel.name)) {
			return
		}
		present(ChannelModesSheet(channel: channel) { [weak channel] modes in
			guard let channel, let session = channel.associatedSession,
			      ChannelActionPermissions(channel: channel, session: session).canChangeModes,
			      let changes = channel.modeInfo?.changeGroups(for: modes),
			      changes.isEmpty == false
			else { return }
			session.sendModes(changes, inChannelNamed: channel.name)
		}) { $0.startSheet() }
	}

	/// Invites `nicknames` to one of `channels`, which are the other channels the
	/// connection is in.
	static func presentChannelInvite(for nicknames: [String], on session: ServerSession, to channels: [String]) {
		if opensAsCommand(.invite(nicknames: nicknames)) {
			return
		}
		present(ChannelInviteSheet(nicknames: nicknames, on: session) { [weak session] channelName in
			guard let session, session.isLoggedIn else { return }
			for nickname in nicknames {
				session.sendInvite(to: nickname, toJoinChannelNamed: channelName)
			}
		}) { $0.start(withChannels: channels) }
	}

	static func presentNicknameChange(for session: ServerSession) {
		if opensAsCommand(.nickname(current: session.userNickname)) {
			return
		}
		present(ServerNicknameChangeSheet(session: session) { [weak session] nickname in
			guard let session, session.isConnected else { return }
			session.changeNickname(nickname)
		}) { $0.startSheet() }
	}

	static func presentSASLSignIn(for session: ServerSession) {
		if opensAsCommand(.saslSignIn) {
			return
		}
		present(SASLSignInSheet(session: session)) { $0.startSheet() }
	}

	/// Registers an account on `session`, connecting first when it is not.
	static func presentAccountRegistration(for session: ServerSession) {
		if opensAsCommand(.registerAccount) {
			return
		}
		present(AccountRegistrationSheet(session: session)) { $0.startSheet() }
	}

	static func presentNicknameColor(for nickname: String) {
		if opensAsCommand(.nicknameColor(nickname: nickname)) {
			return
		}
		present(NicknameColorSheet(nickname: nickname) {
			nicknameColorsChanged()
		}) { $0.startSheet() }
	}
}
