// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Themed window chrome setting")
struct ThemesWindowChromeKeyTests {
	@Test("The sidebars use the system material unless the theme is asked to carry them")
	func defaultsToSystemMaterial() {
		#expect(SettingsKeys.Appearance.themesWindowChrome.defaultValue == false)
		#expect(SettingsKeys.Appearance.all.contains { $0.name == SettingsKeys.Appearance.themesWindowChrome.name })
	}

	@Test("Toggling it redraws the sidebar and the member list at once")
	func reloadsSidebarAndMemberList() {
		let action = SettingsReload.action(forKeys: [SettingsKeys.Appearance.themesWindowChrome.name])

		#expect(action.contains([.sidebar, .memberList]))
	}
}
