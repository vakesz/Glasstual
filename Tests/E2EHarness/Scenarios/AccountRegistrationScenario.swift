import ApplicationServices
import Foundation

/// Register Account against `draft/account-registration`: the form sends
/// `REGISTER`, the server asks for a code, the code step sends `VERIFY`, and
/// the sheet ends on the verified account.
struct AccountRegistrationScenario: Scenario {
	let name = "accountRegistration"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let fixture = AccountRegistrationFixture.self
		try await context.launchAgainstPeer(.accountRegistration)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()

		try await context.driver.menu("registerAccount")
		try await context.fillSheetField(AXID.accountRegistrationAccount, with: fixture.account)
		try await context.fillSheetField(AXID.accountRegistrationEmail, with: fixture.email)
		try await context.fillSheetField(AXID.accountRegistrationPassword, with: fixture.password, secure: true)
		try await context.fillSheetField(AXID.accountRegistrationPasswordVerify, with: fixture.password, secure: true)
		try await context.driver.button(AXID.accountRegistrationSubmit)
		try await context.scriptedEvidence("register=true verified=false")

		try await context.fillSheetField(AXID.accountRegistrationCode, with: fixture.code)
		try await context.driver.button(AXID.accountRegistrationSubmit)
		try await context.until("the sheet shows the verified account") {
			try context.driver.anywhere(AXID.accountRegistrationSuccess) != nil
		}
		try await context.scriptedEvidence(fixture.expectedEvidence)
		try await context.driver.button(AXID.accountRegistrationSubmit)
		try await context.until("Done closes the sheet") {
			try context.driver.anywhere(AXID.accountRegistrationSubmit) == nil
		}
		try await context.quit(peerSeesQuit: true)
	}
}

extension ScenarioContext {
	/// Enters `text` in a field of whichever sheet or window holds it.
	func fillSheetField(_ identifier: String, with text: String, secure: Bool = false) async throws {
		try await driver.fill(identifier, with: text, secure: secure) { try self.driver.anywhere(identifier) }
	}
}
