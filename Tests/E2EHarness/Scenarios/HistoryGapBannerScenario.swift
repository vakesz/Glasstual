import ApplicationServices
import Foundation

/// Rejoining a channel that went on without the user: the catch-up pages
/// forward as far as it goes, fetches the live end and says messages are
/// missing between. Loading them from the banner fetches what lies between
/// and takes the banner down.
struct HistoryGapBannerScenario: Scenario {
	let name = "historyGapBanner"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		let fixture = HistoryFixture.self
		let peer = try await context.launchAgainstPeer(.historyGapBanner)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #e2e")
		try await context.transcript(contains: fixture.firstMarker)
		guard try context.banner(AXID.missingHistoryBanner) == nil else {
			throw HarnessFailure.assertion("The missing-messages banner was up with nothing missing")
		}

		try await context.send("/part #e2e")
		try await context.until("#e2e is left") { try context.rowState("channel", "#e2e") == AXID.RowState.notJoined }
		try await context.send("/join #e2e")
		try await context.transcript(contains: fixture.liveEndMarker)
		try await context.until("the banner says messages are missing") {
			try context.banner(AXID.missingHistoryBanner) != nil
		}
		guard peer.evidence.scripted == "served=24 between=0 around=0" else {
			throw HarnessFailure.assertion("The catch-up did not stop six messages short: \(peer.evidence.scripted ?? "nothing")")
		}
		for marker in fixture.gapMarkers where try context.transcriptContains(marker) {
			throw HarnessFailure.assertion("A message from the gap was shown before it was loaded")
		}

		try await context.driver.press("load the missing messages") {
			try context.banner(AXID.missingHistoryBanner).flatMap {
				try context.driver.find(AXID.missingHistoryLoad, in: $0) ?? context.driver.anywhere(AXID.missingHistoryLoad)
			}
		}
		try await context.until("the banner goes once the messages are loaded") {
			try context.banner(AXID.missingHistoryBanner) == nil && peer.evidence.scripted?.hasPrefix("served=30 ") == true
		}
		try await context.until("the transcript shows the messages from the gap") {
			try fixture.gapMarkers.allSatisfy { try context.transcriptContains($0) }
		}
		try await context.quit(peerSeesQuit: true)
	}
}

extension ScenarioContext {
	/// The banner identified `identifier` over the main window's transcript.
	func banner(_ identifier: String) throws -> AXUIElement? {
		try mainWindow().flatMap { try driver.find(identifier, in: $0) }
	}
}
