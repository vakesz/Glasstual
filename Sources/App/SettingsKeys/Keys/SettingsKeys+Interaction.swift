// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// How the application asks the reader something.
	enum Interaction {
		private static let group = "Interaction -> "

		/// Whether questions open as dialogs or appear in the conversation, and
		/// whether editors open as sheets or as a command in the message field.
		static let style = SettingsKey(group + "Style", default: InteractionStyle.dialogs)

		static let all: [any AnySettingsKey] = [style]
	}
}

/// How the application asks the reader something. The case order is the
/// picker order.
enum InteractionStyle: UInt, CaseIterable, Sendable {
	/// Questions open as alerts and editors as sheets.
	case dialogs = 0
	/// Questions appear in the conversation, answered by a click or a typed
	/// command, and editors open as a command in the message field.
	case conversation = 1
}

extension InteractionStyle: SettingEnum {}

extension InteractionStyle {
	/// What the interaction style picker calls this choice.
	var displayName: LocalizedStringResource {
		switch self {
		case .dialogs: .SettingsLabels.interactionStyleDialogs
		case .conversation: .SettingsLabels.interactionStyleConversation
		}
	}
}
