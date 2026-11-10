import ApplicationServices
import Foundation

/** The credential-consent scenarios: the client is set not to validate the
 certificate and the server offers SASL PLAIN, so before the password goes on the
 wire the client asks its user. `Scenario` runs the connection around these steps;
 the peer's `SASLConsentFixture` records what it actually received. */
enum CredentialConsentScenario {
	private static let passwordField = "server-nickserv-password"

	/** Types the synthetic password into Server Properties and saves it.

	 The secret is stored in the application's own keychain item, which the
	 harness cannot write: it has to come in through the application. The field is
	 on the Identity pane. */
	static func storePassword(driver: AccessibilityDriver) async throws {
		try await driver.menu("Server Properties\u{2026}", in: "Server")
		let sheet = try await propertiesSheet(driver: driver)
		try await driver.selectRow("Identity", from: sheet)
		try await driver.fillSecure(passwordField, with: SASLConsentFixture.secret, from: sheet)
		try await driver.button("Save", from: sheet)
		try await driver.wait("Server Properties sheet closed") { deadline in
			try findPropertiesSheet(driver: driver, deadline: deadline) == nil
		}
	}

	/// Answers the consent alert the way the scenario's kind says.
	static func answer(_ answer: SASLConsentFixture.Answer, driver: AccessibilityDriver) async throws {
		try await driver.credentialConsent(send: answer == .send)
	}

	/// What the peer received must be exactly what the answer allows: no payload
	/// after Don't Send, and one, with the right credentials, after Send Password.
	static func verifyEvidence(_ answer: SASLConsentFixture.Answer) throws {
		let expected = SASLConsentFixture(answer: answer).expectedEvidence
		guard try HarnessFiles.read("sasl-evidence") == expected else {
			throw HarnessFailure.assertion("The peer's SASL evidence did not match the user's answer")
		}
	}

	private static func propertiesSheet(driver: AccessibilityDriver) async throws -> AXUIElement {
		var sheet: AXUIElement?
		try await driver.wait("Server Properties sheet") { deadline in
			sheet = try findPropertiesSheet(driver: driver, deadline: deadline)
			return sheet != nil
		}
		guard let sheet else { throw HarnessFailure.assertion("Server Properties sheet missing") }
		return sheet
	}

	/// The sheet with the properties' own Save button, so another sheet or alert
	/// is never mistaken for it.
	private static func findPropertiesSheet(driver: AccessibilityDriver, deadline: Double) throws -> AXUIElement? {
		try driver.find(from: driver.root, deadline: deadline) { node in
			guard try driver.text(node, kAXRoleAttribute, deadline: deadline) == kAXSheetRole else { return false }
			return try driver.named("Save", role: kAXButtonRole, from: node, deadline: deadline) != nil
		}
	}
}
