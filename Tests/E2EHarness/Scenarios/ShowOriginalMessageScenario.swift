import ApplicationServices
import Foundation

/// Show Original Message on a reply whose original was never received: the
/// server is asked for the messages around it, and the transcript shows them
/// as a window of history with the way back to the live end.
struct ShowOriginalMessageScenario: Scenario {
	let name = "showOriginalMessage"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let fixture = HistoryFixture.self
		let peer = try await context.launchAgainstPeer(.showOriginalMessage)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #e2e")
		try await context.transcript(contains: fixture.replyMarker)
		guard try context.transcriptContains(fixture.originalMarker) == false else {
			throw HarnessFailure.assertion("The original message was shown before it was asked for")
		}

		let transcript = try await context.openTranscriptMenu(at: fixture.replyMarker)
		try await context.driver.press("Show Original Message is offered for a reply") {
			try context.driver.contextMenuItem("transcriptShowOriginalMessage", of: transcript)
		}
		try await context.until("the transcript shows the original message") {
			try context.transcriptContains(fixture.originalMarker) && context.banner(AXID.historyWindowBanner) != nil
		}
		guard peer.evidence.scripted?.hasSuffix("around=1") == true else {
			throw HarnessFailure.assertion("The original message was not asked of the server")
		}
		try await context.driver.press("return to the live end") {
			try context.driver.anywhere(AXID.historyReturnToLive)
		}
		try await context.until("the live end is back") {
			try context.banner(AXID.historyWindowBanner) == nil && context.transcriptContains(fixture.replyMarker)
		}
		try await context.quit(peerSeesQuit: true)
	}
}
