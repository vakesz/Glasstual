import ApplicationServices
import Foundation

enum PluginAndBurstScenarios {
	static func run(kind: ScenarioKind, driver: AccessibilityDriver) async throws {
		try await driver.typeAndSend("/join #e2e")
		try await driver.waitForTranscript("E2E_CHANNEL_READY")
		if kind == .pluginSmiley {
			for (index, enabled) in [false, true, false].enumerated() {
				let settings = try await driver.settingsWindow()
				try await driver.selectRow("Add-ons", from: settings)
				try await driver.selectPreferencePage("Smiley Converter", in: settings)
				try await driver.toggle("Enable Smiley Converter", to: enabled, from: settings)
				try await driver.closeWindow(settings)
				try await driver.selectChannel("#e2e", joined: true)
				let marker = ["E2E_SMILEY_OFF", "E2E_SMILEY_ON", "E2E_SMILEY_OFF_AGAIN"][index]
				try await driver.typeAndSend("/msg fixture " + marker)
				try await driver.selectChannel("#e2e", joined: true)
				try await driver.waitForTranscript(marker + (enabled ? " \u{1F60A}" : " :-)"))
			}
			try HarnessFiles.write("raw; converted; raw via loaded plugin Settings", to: "plugin-effect")
		} else {
			try await driver.typeAndSend("/msg fixture E2E_BURST_START")
			for index in 1 ... 3 {
				guard try !HarnessFiles.exists("burst-complete")
				else { throw HarnessFailure.assertion("Burst ended before UI switching") }
				let settings = try await driver.settingsWindow()
				try await driver.selectRow("General", from: settings)
				try await driver.wait("Settings remains responsive during burst") { deadline in
					try driver.named(
						"Request confirmation before quitting Glasstual",
						role: kAXCheckBoxRole,
						from: settings,
						deadline: deadline
					) != nil
				}
				try await driver.closeWindow(settings)
				try await driver.selectChannel("#e2e", joined: true)
				try await driver.typeAndSend("/msg fixture E2E_BURST_SWITCH_\(index)")
				try await driver.selectChannel("#e2e", joined: true)
				try await driver.waitForTranscript("E2E_BURST_SWITCH_\(index)_ACK")
				try HarnessFiles.write("Settings and channel responded", to: "burst-ui-switch-\(index)")
			}
			try await driver.waitForTranscript("E2E_BURST_END")
			try await driver.wait("burst peer complete and 10002 channel members") { deadline in
				guard try HarnessFiles.exists("burst-complete"), let window = try driver.identified(
					"main-window",
					from: driver.root,
					deadline: deadline
				) else { return false }
				return try driver.text(window, kAXTitleAttribute, deadline: deadline).contains("10,002")
			}
		}
	}
}
