import ApplicationServices
import Foundation

/** Server Properties is a window of its own: an edit marks it edited, closing
 it then asks, Cancel keeps the window and the edit, Save stores the edit and
 a relaunch shows it, and asking for the same server's properties again
 brings the one window forward. */
struct ServerPropertiesWindowScenario: Scenario {
	let name = "serverPropertiesWindow"
	let budget = Duration.seconds(180)
	private let renamed = "E2E Renamed"

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.registration, keepsState: true)
		try await context.server(AXID.RowState.disconnected)
		try await context.openServerProperties()
		try await context.driver.select(AXID.serverPropertiesPane("general")) {
			try context.driver.window(AXID.serverProperties)
		}
		try await context.requireServerPropertiesEdited(false)
		try await context.driver.fill(AXID.serverPropertiesConnectionName, inWindow: AXID.serverProperties, with: renamed)
		try await context.requireServerPropertiesEdited(true)

		try await context.pressCloseButton(of: AXID.serverProperties)
		try await context.answerCloseReview(AXID.alertAlternate(AXID.serverPropertiesCloseReview))
		try await context.until("Cancel keeps the window and the edit") {
			guard let field = try context.driver.element(AXID.serverPropertiesConnectionName, inWindow: AXID.serverProperties)
			else { return false }
			return try context.driver.value(field) == renamed
		}
		try await context.requireServerPropertiesEdited(true)

		try await context.pressCloseButton(of: AXID.serverProperties)
		try await context.answerCloseReview(AXID.alertDefault(AXID.serverPropertiesCloseReview))
		try await context.until("Save closes the window") { try context.driver.window(AXID.serverProperties) == nil }
		try await context.until("the sidebar names the server as saved") {
			try context.rowState("server", renamed) == AXID.RowState.disconnected
		}

		try await context.openServerProperties()
		try await context.driver.menu("mainWindow")
		try await context.until("the main window comes forward") {
			guard let window = try context.mainWindow() else { return false }
			return try context.driver.bool(window, kAXMainAttribute) == true
		}
		try await context.openServerProperties()
		try await context.until("the same window comes forward, and only it") {
			let windows = try context.driver.windows().filter {
				try context.driver.find(AXID.serverPropertiesSave, in: $0, limit: 400) != nil
			}
			guard windows.count == 1 else {
				if windows.count > 1 {
					throw HarnessFailure.assertion("Server Properties opened a second window for the same server")
				}
				return false
			}
			return try context.driver.bool(windows[0], kAXMainAttribute) == true
		}
		try await context.quit(peerSeesQuit: false)

		let first = try context.current
		try await context.launch(seed: nil)
		guard try context.current.pid != first.pid else {
			throw HarnessFailure.assertion("The relaunch did not start a new process")
		}
		try await context.server(AXID.RowState.disconnected, network: renamed)
		try await context.selectRow("server", renamed)
		try await context.openServerProperties()
		try await context.driver.select(AXID.serverPropertiesPane("general")) {
			try context.driver.window(AXID.serverProperties)
		}
		try await context.until("the relaunch shows the saved name") {
			guard let field = try context.driver.element(AXID.serverPropertiesConnectionName, inWindow: AXID.serverProperties)
			else { return false }
			return try context.driver.value(field) == renamed
		}
		try await context.requireServerPropertiesEdited(false)
		try await context.quit(peerSeesQuit: false)
	}
}
