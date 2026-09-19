// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// The identity a new connection is seeded with.
	enum Identity {
		private static let group = "Identity -> "

		static let nickname = SettingsKey(group + "Nickname", default: "Guest")
		static let awayNickname = SettingsKey(group + "Away Nickname", default: "")
		static let username = SettingsKey(group + "Username", default: "glasstual")
		static let realName = SettingsKey(group + "Real Name", default: "Glasstual User")

		static let ctcpVersionMasquerade = SettingsKey(
			group + "CTCP Version Masquerade",
			default: "",
			traits: .unregistered
		)

		static let onboardingCompleted = SettingsKey(group + "Onboarding Completed", default: false)

		static let all: [any AnySettingsKey] = [
			nickname, awayNickname, username, realName, ctcpVersionMasquerade, onboardingCompleted,
		]
	}
}
