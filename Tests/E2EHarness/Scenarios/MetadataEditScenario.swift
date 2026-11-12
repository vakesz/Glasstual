import ApplicationServices
import Foundation

/// The Profile pane of Server Properties sets the user's own display name
/// through `draft/metadata-2`: the server stores it, the pane has nothing left
/// to update, and the member list names the user by it.
struct MetadataEditScenario: Scenario {
	let name = "metadataEdit"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.metadataEdit)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #e2e")
		try await context.transcript(contains: "E2E_CHANNEL_READY")
		try await context.scriptedEvidence("subscribed=true stored=false")

		try await context.openServerProperties()
		try await context.driver.select(AXID.serverPropertiesPane("profile")) {
			try context.driver.window(AXID.serverProperties)
		}
		try await context.until("nothing is stored for the profile yet") {
			try context.profileButton(AXID.serverProfileClear) == false && context.profileButton(AXID.serverProfileUpdate) == false
		}
		try await context.driver.fill(
			AXID.serverProfileDisplayName, inWindow: AXID.serverProperties, with: MetadataFixture.displayName
		)
		try await context.driver.button(AXID.serverProfileUpdate, inWindow: AXID.serverProperties)
		try await context.scriptedEvidence(MetadataFixture.expectedEvidence)
		try await context.until("the pane shows the name the server stored") {
			try context.profileButton(AXID.serverProfileClear) == true && context.profileButton(AXID.serverProfileUpdate) == false
		}
		try await context.close(window: AXID.serverProperties)
		try await context.until("the member list names the user by the display name") {
			guard let window = try context.mainWindow(), let list = try context.driver.find(AXID.memberList, in: window),
			      let row = try context.driver.find(AXID.memberRow("e2euser"), in: list)
			else { return false }
			return try context.driver.string(row, kAXDescriptionAttribute)?.contains(MetadataFixture.displayName) == true
		}
		try await context.quit(peerSeesQuit: true)
	}
}

private extension ScenarioContext {
	/// Whether a button of the Profile pane is enabled, or `nil` while it is not there.
	func profileButton(_ identifier: String) throws -> Bool? {
		try driver.element(identifier, inWindow: AXID.serverProperties).map { try driver.isEnabled($0) }
	}
}
