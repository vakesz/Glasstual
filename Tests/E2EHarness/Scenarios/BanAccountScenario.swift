import ApplicationServices
import Foundation

/** Ban Account in a member's context menu: left out for a member the server
 has not named an account for, and for a logged-in member it asks, then sets
 the account ban the server announced in `ACCOUNTEXTBAN`. */
struct BanAccountScenario: Scenario {
	let name = "banAccount"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.banAccount)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #e2e")
		try await context.transcript(contains: "E2E_CHANNEL_READY")

		let list = try await context.openMemberMenu(BanAccountFixture.memberWithoutAccount)
		/* A context menu leaves out what it cannot do rather than dimming it,
		 so Get Info is there and Ban Account is not. */
		try await context.until("the context menu of a member without an account is open") {
			try context.driver.contextMenuItem("whois", of: list) != nil
		}
		guard try context.driver.contextMenuItem("banAccount", of: list) == nil else {
			throw HarnessFailure.assertion("Ban Account was offered for a member with no known account")
		}
		if let menu = try context.driver.contextMenu(of: list) {
			try context.driver.perform(kAXCancelAction, on: menu)
		}
		try await context.until("context menu closes") { try context.driver.contextMenu(of: list) == nil }

		let table = try await context.openMemberMenu(BanAccountFixture.member)
		try await context.driver.press("Ban Account is enabled for a logged-in member") {
			try context.driver.contextMenuItem("banAccount", of: table)
		}
		try await context.driver.press("confirm the account ban") {
			try context.driver.window(AXID.moderationConfirmation).flatMap {
				try context.driver.find(AXID.alertDefault(AXID.moderationConfirmation), in: $0)
			}
		}
		try await context.until("peer received the account ban") { peer.evidence.banLine != nil }
		guard peer.evidence.banLine == BanAccountFixture.expectedBan else {
			throw HarnessFailure.assertion("The account ban was not the one ACCOUNTEXTBAN announced")
		}
		try await context.quit(peerSeesQuit: true)
	}
}

private extension ScenarioContext {
	/// Selects `nickname` in the member list and opens its context menu.
	/// Returns the member list, which holds the open menu.
	func openMemberMenu(_ nickname: String) async throws -> AXUIElement {
		let list = { () throws -> AXUIElement? in
			guard let window = try self.mainWindow() else { return nil }
			return try self.driver.find(AXID.memberList, in: window)
		}
		try await driver.select(AXID.memberRow(nickname), in: list)
		guard let table = try list(), let member = try driver.find(AXID.memberRow(nickname), in: table) else {
			throw HarnessFailure.assertion("The member's row went away")
		}
		try driver.showMenu(member)
		return table
	}
}
