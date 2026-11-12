// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One `/channelconfig` setting: a control of the Channel Properties sheet,
 reached through the sheet's own model, so the command and the sheet accept
 the same values. */
@MainActor
struct ChannelConfigField {
	let name: String
	let kind: ConfigurationValueKind
	let read: (ChannelPropertiesModel) -> String
	let write: (ChannelPropertiesModel, String) -> Bool

	static func flag(_ name: String, _ keyPath: ReferenceWritableKeyPath<ChannelPropertiesModel, Bool>) -> Self {
		Self(name: name, kind: .flag) { $0[keyPath: keyPath] ? "on" : "off" } write: { model, text in
			guard let value = ConfigurationValueKind.flagValue(text) else { return false }
			model[keyPath: keyPath] = value
			return true
		}
	}

	static func configFlag(_ name: String, _ keyPath: WritableKeyPath<ConversationConfig, Bool>) -> Self {
		Self(name: name, kind: .flag) { $0.config[keyPath: keyPath] ? "on" : "off" } write: { model, text in
			guard let value = ConfigurationValueKind.flagValue(text) else { return false }
			model.config[keyPath: keyPath] = value
			return true
		}
	}

	static func text(_ name: String, _ keyPath: WritableKeyPath<ConversationConfig, String?>) -> Self {
		Self(name: name, kind: .text) { $0.config[keyPath: keyPath] ?? "" } write: { model, text in
			model.config[keyPath: keyPath] = text.isEmpty ? nil : text
			return true
		}
	}

	static let all: [ChannelConfigField] = [
		.configFlag("autojoin", \.autoJoin),
		Self(name: "events", kind: .choice(GeneralEventMessageDisplay.allCases.map(\.rawValue))) {
			$0.config.generalEventMessageDisplay.rawValue
		} write: { model, text in
			guard let display = GeneralEventMessageDisplay(rawValue: text.lowercased()) else { return false }
			model.config.generalEventMessageDisplay = display
			return true
		},
		.configFlag("ignore-highlights", \.ignoreHighlights),
		.flag("inline-media", \.inlineMediaOverride),
		.flag("muted", \.isMuted),
		.configFlag("unread-count", \.showsUnreadCount),
		.configFlag("favorite", \.isFavorite),
		.text("label", \.label),
		.text("modes", \.defaultModes),
		.text("topic", \.defaultTopic),
		Self(name: "key", kind: .secret) { _ in "" } write: { model, text in
			model.secretKey = text
			return true
		},
	]

	static func named(_ name: String) -> ChannelConfigField? {
		all.first { $0.name == name.lowercased() }
	}
}
