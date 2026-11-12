// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** `/serverconfig`, `/channelconfig` and `/setcolor` with a colour.

 Each edit is made on a fresh copy of the editor's model, validated by the
 model exactly as the sheet validates, and saved the way the sheet saves. A
 secret is never read from the command line: naming a secret setting alone asks
 for it in a secure field, as an alert or in the conversation. */
@MainActor
final class ConfigurationCommands: ConfigurationCommanding {
	// MARK: - Server

	func performServerConfiguration(_ arguments: String, on session: ServerSession) -> [String] {
		let (name, value) = Self.split(arguments)
		switch name.lowercased() {
		case "", "list":
			let model = ServerPropertiesModel(config: session.config)
			return [String(localized: .IRC.configListHeader(session.config.connectionName))]
				+ ServerConfigField.all.map { Self.describe($0.name, kind: $0.kind, value: $0.read(model)) }
		case "reset":
			guard let field = ServerConfigField.named(value) else { return unknownSetting(value, command: "/serverconfig") }
			guard field.isResettable else {
				return [String(localized: .IRC.configNotResettable(field.name, "/serverconfig \(field.name)"))]
			}
			let defaults = ServerPropertiesModel(config: ServerConfig())
			return setServerField(field, to: field.kind == .secret ? "" : field.read(defaults), on: session)
		default:
			guard let field = ServerConfigField.named(name) else { return unknownSetting(name, command: "/serverconfig") }
			if field.kind == .secret {
				guard value.isEmpty else {
					return [String(localized: .IRC.configSecretOnCommandLine("/serverconfig \(field.name)"))]
				}
				askForSecret(named: field.name, title: Self.secretTitle(field.name), on: session) { session, secret in
					self.setServerField(field, to: secret, on: session)
				}
				return []
			}
			guard value.isEmpty == false else {
				return [Self.describe(field.name, kind: field.kind, value: field.read(ServerPropertiesModel(config: session.config)))]
			}
			return setServerField(field, to: value, on: session)
		}
	}

	private func setServerField(_ field: ServerConfigField, to value: String, on session: ServerSession) -> [String] {
		let model = ServerPropertiesModel(config: session.config)
		guard field.write(model, value) else {
			return [String(localized: .IRC.configInvalidValue(field.name, value, field.kind.accepted))]
		}
		if let fault = model.validationFault {
			return [fault.message]
		}
		guard let config = model.submittedConfig() else { return [] }
		MenuSheetPresenter.applyServerConfiguration(config, to: session)
		return [Self.changed(field.name, kind: field.kind, value: field.read(model))]
	}

	// MARK: - Channel

	func performChannelConfiguration(_ arguments: String, on session: ServerSession, target: Conversation?) -> [String] {
		var (first, rest) = Self.split(arguments)
		let channel: Conversation?
		if session.stringIsChannelName(first) {
			channel = session.findConversation(first)
			(first, rest) = Self.split(rest)
		} else {
			channel = target?.isChannel == true ? target : nil
		}
		guard let channel, channel.isChannel,
		      session.config.conversationList.contains(where: { $0.uniqueIdentifier == channel.uniqueIdentifier })
		else {
			return [String(localized: .IRC.channelConfigNeedsChannel)]
		}
		switch first.lowercased() {
		case "", "list":
			let model = channelModel(for: channel, on: session)
			return [String(localized: .IRC.configListHeader(channel.name))]
				+ ChannelConfigField.all.map { Self.describe($0.name, kind: $0.kind, value: $0.read(model)) }
		case "reset":
			guard let field = ChannelConfigField.named(rest) else { return unknownSetting(rest, command: "/channelconfig") }
			let defaults = ChannelPropertiesModel(config: ConversationConfig.seed(withName: channel.name))
			return setChannelField(field, to: field.kind == .secret ? "" : field.read(defaults), on: channel, session: session)
		default:
			guard let field = ChannelConfigField.named(first) else { return unknownSetting(first, command: "/channelconfig") }
			if field.kind == .secret {
				guard rest.isEmpty else {
					return [String(localized: .IRC.configSecretOnCommandLine("/channelconfig \(channel.name) \(field.name)"))]
				}
				askForSecret(
					named: field.name, title: String(localized: .ChannelProperties.channelKeyPlaceholder), on: session
				) { [weak channel] session, secret in
					guard let channel else { return [] }
					return self.setChannelField(field, to: secret, on: channel, session: session)
				}
				return []
			}
			guard rest.isEmpty == false else {
				return [Self.describe(field.name, kind: field.kind, value: field.read(channelModel(for: channel, on: session)))]
			}
			return setChannelField(field, to: rest, on: channel, session: session)
		}
	}

	private func channelModel(for channel: Conversation, on session: ServerSession) -> ChannelPropertiesModel {
		ChannelPropertiesModel(
			config: channel.config,
			session: session,
			siblingNames: ChannelPropertiesSheet.siblingNames(
				in: session.config.conversationList, excluding: channel.uniqueIdentifier
			)
		)
	}

	private func setChannelField(
		_ field: ChannelConfigField,
		to value: String,
		on channel: Conversation,
		session: ServerSession
	) -> [String] {
		let model = channelModel(for: channel, on: session)
		guard field.write(model, value) else {
			return [String(localized: .IRC.configInvalidValue(field.name, value, field.kind.accepted))]
		}
		guard model.validateForSubmission() else {
			return [model.channelNameValidationMessage ?? String(localized: .IRC.configInvalidValue(
				field.name,
				value,
				field.kind.accepted
			))]
		}
		if model.secretKeyIsTooLong, let caption = model.secretKeyLengthCaption {
			return [caption]
		}
		MenuSheetPresenter.applyChannelConfiguration(model.submittedConfig, to: channel)
		return [Self.changed(field.name, kind: field.kind, value: field.read(model))]
	}

	// MARK: - Nickname colour

	func setNicknameColor(_ value: String, for nickname: String) -> [String] {
		if value.lowercased() == "reset" {
			NicknameColors.setOverride(nil, for: nickname)
			MenuSheetPresenter.nicknameColorsChanged()
			return [String(localized: .IRC.nicknameColorReset(nickname))]
		}
		guard let color = Self.color(fromHex: value) else {
			return [String(localized: .IRC.nicknameColorInvalid(value))]
		}
		NicknameColors.setOverride(color, for: nickname)
		MenuSheetPresenter.nicknameColorsChanged()
		return [String(localized: .IRC.nicknameColorPinned(nickname, value.lowercased()))]
	}

	/// `#rrggbb`, with or without the hash.
	static func color(fromHex text: String) -> NSColor? {
		let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
		guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
		return NSColor(
			srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
			green: CGFloat((value >> 8) & 0xFF) / 255,
			blue: CGFloat(value & 0xFF) / 255,
			alpha: 1
		)
	}

	// MARK: - Shared

	/// The question asking for a secret setting, in a secure field.
	static func secretRequest(title: String, connectionName: String) -> AlertRequest {
		AlertRequest(
			title: title,
			body: String(localized: .IRC.configSecretPromptBody(connectionName)),
			defaultButton: PromptStrings.Action.save,
			alternateButton: PromptStrings.Action.cancel,
			field: .secure(placeholder: title),
			keywords: [.default: .submit, .alternate: .cancel]
		)
	}

	/// Asks for a secret setting in a secure field and saves what comes back.
	private func askForSecret(
		named _: String,
		title: String,
		on session: ServerSession,
		save: @escaping @MainActor (ServerSession, String) -> [String]
	) {
		session.requestAnswer(
			Self.secretRequest(title: title, connectionName: session.config.connectionName),
			boundToConnection: false,
			unattended: .alternate
		) { session, answer in
			guard answer.response == .default, let secret = answer.text else { return }
			for line in save(session, secret) {
				session.printDebugInformation(line)
			}
		}
	}

	private static func secretTitle(_ name: String) -> String {
		switch name {
		case "server-password": String(localized: .ServerProperties.serverPassword)
		case "nickname-password": String(localized: .ServerProperties.nickservOrSaslPassword)
		case "proxy-password": String(localized: .IRC.configProxyPasswordTitle)
		default: String(localized: .ServerProperties.saslBearerToken)
		}
	}

	private func unknownSetting(_ name: String, command: String) -> [String] {
		[String(localized: .IRC.configUnknownSetting(name, "\(command) list"))]
	}

	private static func describe(_ name: String, kind: ConfigurationValueKind, value: String) -> String {
		kind == .secret ? name : String(localized: .IRC.configSettingValue(name, value))
	}

	private static func changed(_ name: String, kind: ConfigurationValueKind, value: String) -> String {
		kind == .secret || value.isEmpty
			? String(localized: .IRC.configSettingUpdated(name))
			: String(localized: .IRC.configSettingChanged(name, value))
	}

	/// The first word and the rest of the line.
	private static func split(_ text: String) -> (String, String) {
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		guard let space = trimmed.firstIndex(where: \.isWhitespace) else { return (trimmed, "") }
		return (String(trimmed[..<space]), trimmed[space...].trimmingCharacters(in: .whitespaces))
	}
}
