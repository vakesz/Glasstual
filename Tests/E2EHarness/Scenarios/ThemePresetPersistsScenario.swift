import Foundation

/// Settings > Style: choosing the Classic transcript theme preset stores that
/// theme, and the relaunched application keeps it.
struct ThemePresetPersistsScenario: Scenario {
	let name = "themePresetPersists"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.registration, keepsState: true)
		try await context.server(AXID.RowState.disconnected)
		try await context.openSettings()
		try await context.selectSettingsPage("style")
		try await context.choose(AXID.settingsThemePreset("classic"), fromMenu: AXID.settingsThemePreset, inWindow: AXID.settingsWindow)
		try await context.storedSetting(SettingsKey.transcriptTheme, "is the Classic theme", Self.isClassic)
		try await context.close(window: AXID.settingsWindow)
		try await context.quit(peerSeesQuit: false)

		let first = try context.current
		try await context.launch(seed: nil)
		guard try context.current.pid != first.pid else {
			throw HarnessFailure.assertion("The relaunch did not start a new process")
		}
		try await context.until("main window after relaunch") { try context.mainWindow() != nil }
		try await context.storedSetting(SettingsKey.transcriptTheme, "is still the Classic theme", Self.isClassic)
		try await context.quit(peerSeesQuit: false)
	}

	/// The stored theme is a property list; a preset is stored under its own,
	/// unlocalized name.
	private static func isClassic(_ value: Any?) -> Bool {
		guard let data = value as? Data,
		      let theme = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		else { return false }
		return theme["name"] as? String == "Classic"
	}
}
