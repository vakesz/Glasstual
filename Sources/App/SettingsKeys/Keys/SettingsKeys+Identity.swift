// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// The identity a new connection is seeded with.
	enum Identity {
		private static let group = "Identity -> "
		/// Bounds imported free text: a multi-megabyte nickname would persist,
		/// render and re-send on the wire.
		private static let maximumIdentityLength = 512

		static let nickname = SettingsKey(
			group + "Nickname",
			default: "Guest",
			validation: { $0.count <= maximumIdentityLength }
		)
		static let awayNickname = SettingsKey(
			group + "Away Nickname",
			default: "",
			validation: { $0.count <= maximumIdentityLength }
		)
		static let username = SettingsKey(
			group + "Username",
			default: "glasstual",
			validation: { $0.count <= maximumIdentityLength }
		)
		static let realName = SettingsKey(
			group + "Real Name",
			default: "Glasstual User",
			validation: { $0.count <= maximumIdentityLength }
		)

		static let ctcpVersionMasquerade = SettingsKey(
			group + "CTCP Version Masquerade",
			default: "",
			traits: .unregistered,
			validation: { $0.count <= maximumIdentityLength }
		)

		static let onboardingCompleted = SettingsKey(group + "Onboarding Completed", default: false)

		static let all: [any AnySettingsKey] = [
			nickname, awayNickname, username, realName, ctcpVersionMasquerade, onboardingCompleted,
		]
	}
}
