// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum MenuWindowPolicy {
	static let alertSuppressionPrefix = SettingsKeys.Families.alertSuppression.pattern

	static func appearance(for command: MenuCommand?) -> PreferredAppearance? {
		switch command {
		case .appearanceSystem: .inherited
		case .appearanceLight: .light
		case .appearanceDark: .dark
		default: nil
		}
	}

	/// Channels first, then everything else, each group ordered by name. The
	/// sidebar's sort never mixes the two.
	static func channelsOrderedBeforeDirectConversations(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
		/* Both directions have to be answered. Without the second branch a
		 one-to-one conversation and a channel compare as "unordered" one way
		 and "ordered" the other, which is not a strict weak ordering and lets
		 sort(by:) produce garbage. */
		if lhs.isChannel != rhs.isChannel {
			return lhs.isChannel
		}
		return lhs.name.lowercased().compare(rhs.name.lowercased()) == .orderedAscending
	}
}
