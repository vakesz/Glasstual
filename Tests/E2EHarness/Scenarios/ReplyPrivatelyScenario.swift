import ApplicationServices
import Foundation

/// Reply Privately on a channel message: what is typed next goes to the
/// message's sender alone, tagged with the channel and the message it
/// answers, and the sender's private answer is filed in the channel rather
/// than in a conversation of its own.
struct ReplyPrivatelyScenario: Scenario {
	let name = "replyPrivately"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let fixture = PrivateReplyFixture.self
		try await context.launchAgainstPeer(.replyPrivately)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #e2e")
		try await context.transcript(contains: fixture.original)

		let transcript = try await context.openTranscriptMenu(at: fixture.original)
		try await context.driver.press("Reply Privately is offered for another member's message") {
			try context.driver.contextMenuItem("transcriptReplyPrivately", of: transcript)
		}
		try await context.until("the message field says the next message is a private reply") {
			try context.banner(AXID.inputPrivateReplyBanner) != nil
		}
		try await context.send(fixture.reply)
		try await context.until("sending ends the private reply") {
			try context.banner(AXID.inputPrivateReplyBanner) == nil
		}
		try await context.scriptedEvidence(fixture.expectedEvidence)
		try await context.transcript(contains: fixture.acknowledgement)
		guard try context.isSelected("channel", "#e2e"),
		      try context.rowState("direct", "fixture") == nil, try context.rowState("direct-chat", "=fixture") == nil
		else { throw HarnessFailure.assertion("The private answer opened a conversation instead of staying in the channel") }
		try await context.quit(peerSeesQuit: true)
	}
}
