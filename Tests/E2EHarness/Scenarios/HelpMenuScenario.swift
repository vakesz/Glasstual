import Foundation

/// Help > Glasstual Help is in the Help menu and enabled. Choosing it opens
/// the system Help Viewer, a process of its own the harness leaves alone.
struct HelpMenuScenario: Scenario {
	let name = "helpMenu"
	let budget = Duration.seconds(90)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.registration)
		try await context.server(AXID.RowState.disconnected)
		let item = try await context.driver.enabledMenuItem("glasstualHelp")
		guard let help = try context.driver.menuItem("helpMenu"),
		      try context.driver.find(AXID.menu("glasstualHelp"), in: help) != nil
		else {
			throw HarnessFailure.assertion("Glasstual Help is not in the Help menu")
		}
		guard try context.driver.isEnabled(item) else {
			throw HarnessFailure.assertion("Glasstual Help is disabled")
		}
		try await context.quit(peerSeesQuit: false)
	}
}
