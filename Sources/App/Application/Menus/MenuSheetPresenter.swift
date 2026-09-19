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
		let window = Self.window
		window.sheetModel.dismissPresentedSheet()
		let sheet = make()
		sheet.window = window
		start(sheet)
	}

	private static var window: MainWindow {
		AppServices.delegate.mainWindow
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
		present(ServerPropertiesSheet(session: session) { [weak session] config in
			guard let directory = AppServices.chatSession else { return }
			guard let session else {
				let created = directory.createSession(with: config)
				window.expandSession(created)
				directory.save()
				return
			}
			let encodingChanged = config.primaryEncoding != session.config.primaryEncoding
			session.updateConfig(config)
			if encodingChanged {
				window.reloadTheme()
			}
			window.reloadChatItemGroup(session)
			directory.save()
		}) { $0.start(at: destination) }
	}

	/// Opens the channel sheet, on an existing channel or on a new one for
	/// `session`.
	static func presentChannelProperties(for channel: Conversation?, on session: ServerSession?) {
		let save: (ConversationConfig) -> Void = { [weak session, weak channel] config in
			guard let directory = AppServices.chatSession, let session else { return }
			guard let channel else {
				_ = directory.createConversation(with: config, on: session)
				window.expandSession(session)
				return
			}
			channel.updateConfig(config)
			directory.save()
		}
		present(channel.map { ChannelPropertiesSheet(channel: $0, onSave: save) }
			?? ChannelPropertiesSheet(config: nil, onSession: session, onSave: save)) { $0.startSheet() }
	}

	static func presentChannelTopic(for channel: Conversation) {
		guard ChannelActionPermissions(channel: channel, session: channel.associatedSession).canModifyTopic else { return }
		present(ChannelTopicSheet(channel: channel) { [weak channel] topic in
			guard let channel, let session = channel.associatedSession,
			      ChannelActionPermissions(channel: channel, session: session).canModifyTopic
			else { return }
			session.sendTopic(to: topic, in: channel)
		}) { $0.startSheet() }
	}

	static func presentChannelModes(for channel: Conversation) {
		guard ChannelActionPermissions(channel: channel, session: channel.associatedSession).canChangeModes else { return }
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
		present(ChannelInviteSheet(nicknames: nicknames, on: session) { [weak session] channelName in
			guard let session, session.isLoggedIn else { return }
			for nickname in nicknames {
				session.sendInvite(to: nickname, toJoinChannelNamed: channelName)
			}
		}) { $0.start(withChannels: channels) }
	}

	static func presentNicknameChange(for session: ServerSession) {
		present(ServerNicknameChangeSheet(session: session) { [weak session] nickname in
			guard let session, session.isConnected else { return }
			session.changeNickname(nickname)
		}) { $0.startSheet() }
	}

	static func presentNicknameColor(for nickname: String) {
		present(NicknameColorSheet(nickname: nickname) {
			window.reloadTheme()
			/* The transcript is redrawn by the theme reload; the member list's
			 avatars take their pinned colours from a snapshot the list reads
			 when its presentation is invalidated, and nothing else invalidates
			 it here. */
			window.memberList.invalidatePresentation()
		}) { $0.startSheet() }
	}
}
