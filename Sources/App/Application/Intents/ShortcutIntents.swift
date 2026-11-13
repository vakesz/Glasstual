// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents

/** Sends literal text to a conversation, after the person confirms it.

 The confirmation shows the text and the destination, because the text may
 come from another shortcut or from Siri. A message that starts with a slash is
 sent as it is; it is never run as a command. */
struct SendMessageIntent: AppIntent {
	static let title = LocalizedStringResource("send-message-title", table: "ShortcutIntents")
	static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
		"send-message-description",
		table: "ShortcutIntents"
	))

	@Parameter(title: LocalizedStringResource("conversation-parameter", table: "ShortcutIntents"))
	var conversation: ConversationEntity

	@Parameter(title: LocalizedStringResource("message-parameter", table: "ShortcutIntents"))
	var text: String

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let actions = IntentCatalog.actions()
		let message = try IntentMessage.validated(text)
		try await requestConfirmation(
			actionName: .send,
			dialog: IntentDialog(.ShortcutIntents.sendMessageConfirmation(message, conversation.name, conversation.serverName))
		)
		try await actions.sendMessage(message, toConversation: conversation.id)
		return .result(dialog: IntentDialog(.ShortcutIntents.sendMessageDone(conversation.name)))
	}
}

struct JoinChannelIntent: AppIntent {
	static let title = LocalizedStringResource("join-channel-title", table: "ShortcutIntents")
	static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
		"join-channel-description",
		table: "ShortcutIntents"
	))

	@Parameter(title: LocalizedStringResource("server-parameter", table: "ShortcutIntents"))
	var server: ServerEntity

	@Parameter(title: LocalizedStringResource("channel-parameter", table: "ShortcutIntents"))
	var channel: String

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		let name = try IntentMessage.channelName(channel)
		try await IntentCatalog.actions().joinChannel(name, onServer: server.id)
		return .result(dialog: IntentDialog(.ShortcutIntents.joinChannelDone(name, server.name)))
	}
}

struct ConnectServerIntent: AppIntent {
	static let title = LocalizedStringResource("connect-title", table: "ShortcutIntents")
	static let description: IntentDescription? = IntentDescription(LocalizedStringResource("connect-description", table: "ShortcutIntents"))

	@Parameter(title: LocalizedStringResource("server-parameter", table: "ShortcutIntents"))
	var server: ServerEntity

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		try IntentCatalog.actions().connect(server: server.id)
		return .result(dialog: IntentDialog(.ShortcutIntents.connectDone(server.name)))
	}
}

struct DisconnectServerIntent: AppIntent {
	static let title = LocalizedStringResource("disconnect-title", table: "ShortcutIntents")
	static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
		"disconnect-description",
		table: "ShortcutIntents"
	))

	@Parameter(title: LocalizedStringResource("server-parameter", table: "ShortcutIntents"))
	var server: ServerEntity

	@MainActor
	func perform() async throws -> some IntentResult & ProvidesDialog {
		try IntentCatalog.actions().disconnect(server: server.id)
		return .result(dialog: IntentDialog(.ShortcutIntents.disconnectDone(server.name)))
	}
}

/// Selects a conversation. Spotlight runs this for an indexed conversation too.
struct OpenConversationIntent: OpenIntent {
	static let title = LocalizedStringResource("open-conversation-title", table: "ShortcutIntents")
	static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
		"open-conversation-description",
		table: "ShortcutIntents"
	))

	@Parameter(title: LocalizedStringResource("conversation-parameter", table: "ShortcutIntents"))
	var target: ConversationEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		try IntentCatalog.actions().openConversation(id: target.id)
		return .result()
	}
}

/// Each phrase is the English key of its translations in `AppShortcuts.xcstrings`.
struct GlasstualShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: OpenConversationIntent(),
			phrases: ["Open \(\.$target) in \(.applicationName)"],
			shortTitle: LocalizedStringResource("open-conversation-title", table: "ShortcutIntents"),
			systemImageName: "bubble.left.and.bubble.right"
		)
		AppShortcut(
			intent: SendMessageIntent(),
			phrases: ["Send a message with \(.applicationName)"],
			shortTitle: LocalizedStringResource("send-message-title", table: "ShortcutIntents"),
			systemImageName: "paperplane"
		)
		AppShortcut(
			intent: JoinChannelIntent(),
			phrases: ["Join a channel in \(.applicationName)"],
			shortTitle: LocalizedStringResource("join-channel-title", table: "ShortcutIntents"),
			systemImageName: "number"
		)
		AppShortcut(
			intent: ConnectServerIntent(),
			phrases: ["Connect \(\.$server) in \(.applicationName)"],
			shortTitle: LocalizedStringResource("connect-title", table: "ShortcutIntents"),
			systemImageName: "bolt.horizontal"
		)
		AppShortcut(
			intent: DisconnectServerIntent(),
			phrases: ["Disconnect \(\.$server) in \(.applicationName)"],
			shortTitle: LocalizedStringResource("disconnect-title", table: "ShortcutIntents"),
			systemImageName: "bolt.horizontal.circle"
		)
	}
}
