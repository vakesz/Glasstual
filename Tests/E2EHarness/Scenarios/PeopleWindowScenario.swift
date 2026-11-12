import ApplicationServices
import Foundation

/// Window > People opens the server's address book in a window of its own,
/// an ignore entry added there is saved at once, and a relaunch lists it.
struct PeopleWindowScenario: Scenario {
	let name = "peopleWindow"
	let budget = Duration.seconds(150)
	private let hostmask = "e2etroll!*@*"

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.registration, keepsState: true)
		try await context.server(AXID.RowState.disconnected)
		try await context.openPeople()
		try await context.choose(AXID.addressBookAddIgnore, fromMenu: AXID.addressBookAdd, inWindow: AXID.addressBookWindow)
		try await context.driver.fill(AXID.addressBookEntryHostmask, inWindow: AXID.addressBookWindow, with: hostmask)
		try await context.driver.button(AXID.addressBookEntrySave, inWindow: AXID.addressBookWindow)
		try await context.requirePeopleEntry(hostmask)
		try await context.storedSetting(SettingsKey.serverSessions, "holds the ignore entry") { value in
			guard let value else { return false }
			return String(describing: value).contains(hostmask)
		}
		try await context.close(window: AXID.addressBookWindow)
		try await context.quit(peerSeesQuit: false)

		let first = try context.current
		try await context.launch(seed: nil)
		guard try context.current.pid != first.pid else {
			throw HarnessFailure.assertion("The relaunch did not start a new process")
		}
		try await context.server(AXID.RowState.disconnected)
		try await context.selectRow("server", ScenarioContext.network)
		try await context.openPeople()
		try await context.requirePeopleEntry(hostmask)
		try await context.quit(peerSeesQuit: false)
	}
}

private extension ScenarioContext {
	/// Chooses Window > People and waits for its window.
	func openPeople() async throws {
		try await driver.menu("addressBook")
		try await until("People window") { try driver.window(AXID.addressBookWindow) != nil }
	}

	/// Waits until the People list shows the entry for `hostmask`.
	func requirePeopleEntry(_ hostmask: String) async throws {
		try await until("People lists \(hostmask)") {
			guard let list = try driver.element(AXID.addressBookList, inWindow: AXID.addressBookWindow) else {
				return false
			}
			return try driver.find(AXID.addressBookEntry(hostmask), in: list) != nil
		}
	}
}
