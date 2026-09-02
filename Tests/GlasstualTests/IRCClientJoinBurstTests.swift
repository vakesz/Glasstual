/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** A channel view that draws nothing but answers the print completion, which is
 where the unread count, the highlight badge and the notification are decided.
 The real controller supplies the rendered line number and whether the line
 highlighted; nothing here renders, so both are stated by the test. */
@MainActor
private final class GLTCompletingPresentation: TreeItemPresentation {
	private(set) var printedLines: [LogLine] = []
	var isHighlight = false
	weak var client: IRCClient?
	weak var channel: IRCChannel?

	nonisolated let presentationIdentifier = "join-burst-presentation" // nonisolated: let

	func print(_ logLine: LogLine, completionBlock: LogControllerPrintOperationCompletion?) {
		printedLines.append(logLine)

		guard let completionBlock, let client else { return }

		completionBlock(LogControllerPrintOperationContext(
			client: client,
			channel: channel,
			highlight: isHighlight,
			logLine: logLine,
			lineNumber: "\(printedLines.count)"
		))
	}

	func lastPrintedLine() -> LogLine? {
		printedLines.last
	}

	nonisolated func setTopic(_: String?) {} // nonisolated: pure
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber _: String,
		state _: LogLineDeliveryState,
		messageIdentifier _: String?,
		reason _: String?
	) {}
	func prependHistoricLogLines(_: [LogLine]) {}
	func prepareForPermanentDestruction() {}
	func prepareForApplicationTermination() {}
}

/** The whole point of the grace period is what the user sees after a bouncer
 puts them back in a channel: the replay prints, and nothing about it counts.
 These drive the production inbound path — parse, JOIN, PRIVMSG, print, print
 completion — because the suppression only means anything if it survives every
 hop between the wire and the badge. */
@MainActor
@Suite("Post-join burst suppression", .serialized)
struct IRCClientJoinBurstTests {
	/// Nothing here should reach the real notification centre; a test that
	/// posted one would put a banner in front of whoever ran the suite.
	private func withNotificationsSilenced(_ body: () throws -> Void) rethrows {
		let controller = SharedApplication.sharedNotificationController()
		let wasDisabled = controller.areNotificationsDisabled
		defer { controller.areNotificationsDisabled = wasDisabled }

		controller.areNotificationsDisabled = true

		try body()
	}

	private func makeClient() -> GLTTestClient {
		let client = GLTTestClient()
		client.linePrintObserver = nil
		client.enableCapability(.serverTime)
		client.enableCapability(.messageTags)
		client.enableCapability(.readMarker)
		client.isLoggedIn = true
		client.userNickname = "mara"

		return client
	}

	private func stamp(_ date: Date) -> String {
		sharedISOStandardDateFormatter().string(from: date)
	}

	private func message(_ line: String, on client: IRCClient) throws -> Message {
		try #require(Message(line: line, on: client))
	}

	/// Joins `#chat` as the local user at `joinedAt` and hands back the channel
	/// with a view attached, exactly as the production JOIN path leaves it.
	private func joinedChannel(
		on client: GLTTestClient,
		at joinedAt: Date,
		drawnInto presentation: GLTCompletingPresentation
	) throws -> IRCChannel {
		let join = try message("@time=\(stamp(joinedAt)) :mara!u@h JOIN #chat", on: client)

		client.receiveJoin(join)

		let channel = try #require(client.findChannel("#chat"))
		presentation.client = client
		presentation.channel = channel
		channel.presentation = presentation

		return channel
	}

	@Test("A line replayed within the grace period prints without counting as unread")
	func replayedLineInsideTheWindowIsNotUnread() throws {
		try withNotificationsSilenced {
			let client = makeClient()
			let presentation = GLTCompletingPresentation()
			let now = Date()
			let channel = try joinedChannel(on: client, at: now, drawnInto: presentation)

			#expect(channel.joinedAt != nil)

			/* Stamped five seconds before the join and arriving now: said while
			 the user was away, so a bouncer is replaying it. */
			let replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :did you see this",
				on: client
			)

			#expect(client.lineArrivedAlreadySeen(replayed, in: channel))

			client.receivePrivmsgAndNotice(replayed)

			#expect(presentation.printedLines.last?.messageBody == "did you see this")
			#expect(channel.treeUnreadCount == 0)
			#expect(channel.dockUnreadCount == 0)
			#expect(channel.nicknameHighlightCount == 0)
			#expect(channel.isUnread == false)
		}
	}

	@Test("A JOIN that is itself replayed opens the window from its arrival")
	func replayedJoinIsMeasuredFromArrival() throws {
		try withNotificationsSilenced {
			let client = makeClient()
			let presentation = GLTCompletingPresentation()
			let now = Date()
			/* A bouncer that replays the JOIN stamps it with when it happened,
			 minutes ago; measured from that stamp the window would already be
			 shut when the burst behind it arrives. */
			let channel = try joinedChannel(on: client, at: now.addingTimeInterval(-120), drawnInto: presentation)
			let joinedAt = try #require(channel.joinedAt)

			#expect(abs(joinedAt.timeIntervalSince(now)) < 5)

			let replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :while you were out",
				on: client
			)

			#expect(client.lineArrivedAlreadySeen(replayed, in: channel))

			client.receivePrivmsgAndNotice(replayed)

			#expect(presentation.printedLines.last?.messageBody == "while you were out")
			#expect(channel.isUnread == false)
		}
	}

	@Test("A highlight in the replayed burst raises no badge either")
	func replayedHighlightInsideTheWindowRaisesNoBadge() throws {
		try withNotificationsSilenced {
			let client = makeClient()
			let presentation = GLTCompletingPresentation()
			presentation.isHighlight = true
			let now = Date()
			let channel = try joinedChannel(on: client, at: now, drawnInto: presentation)
			let replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :mara: ping",
				on: client
			)

			client.receivePrivmsgAndNotice(replayed)

			#expect(presentation.printedLines.count == 1)
			#expect(channel.nicknameHighlightCount == 0)
			#expect(channel.treeUnreadCount == 0)
		}
	}

	@Test("A live line said after the grace period counts as unread")
	func liveLineOutsideTheWindowIsUnread() throws {
		try withNotificationsSilenced {
			let client = makeClient()
			let presentation = GLTCompletingPresentation()
			let now = Date()
			/* Joined twenty seconds ago: past the grace period, but not so far
			 back that the JOIN reads as a replayed one measured from arrival. */
			let channel = try joinedChannel(
				on: client,
				at: now.addingTimeInterval(-20),
				drawnInto: presentation
			)
			let live = try message("@time=\(stamp(now)) :bob!u@h PRIVMSG #chat :hello", on: client)

			#expect(client.lineArrivedAlreadySeen(live, in: channel) == false)

			client.receivePrivmsgAndNotice(live)

			#expect(presentation.printedLines.last?.messageBody == "hello")
			#expect(channel.treeUnreadCount == 1)
			#expect(channel.isUnread)
		}
	}

	@Test("A line the server already reported as read stays out of the unread count")
	func lineBehindTheReadMarkerIsNotUnread() throws {
		try withNotificationsSilenced {
			let client = makeClient()
			let presentation = GLTCompletingPresentation()
			let now = Date()
			let channel = try joinedChannel(
				on: client,
				at: now.addingTimeInterval(-20),
				drawnInto: presentation
			)
			let marker = try message(
				":irc.example.net MARKREAD #chat timestamp=\(stamp(now))",
				on: client
			)

			client.receiveReadMarker(marker)

			#expect(client.readMarkerSentDates[channel.uniqueIdentifier] != nil)

			let behindTheMarker = try message(
				"@time=\(stamp(now.addingTimeInterval(-1))) :bob!u@h PRIVMSG #chat :old news",
				on: client
			)

			client.receivePrivmsgAndNotice(behindTheMarker)

			#expect(presentation.printedLines.last?.messageBody == "old news")
			#expect(channel.treeUnreadCount == 0)
		}
	}

	@Test("The replay does not push the server's read marker past what the user has seen")
	func replayedLinesDoNotAdvanceTheReadMarker() throws {
		try withNotificationsSilenced {
			let client = makeClient()
			let presentation = GLTCompletingPresentation()
			let now = Date()
			let channel = try joinedChannel(on: client, at: now, drawnInto: presentation)
			/* Visible in the key window but not selected, which is the state that
			 otherwise marks every printed line as read. */
			client.recordedOutput.windowIsKey = true
			client.recordedOutput.visibleItems = [channel]

			let replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :replayed",
				on: client
			)

			client.receivePrivmsgAndNotice(replayed)

			#expect(client.readMarkerPendingChannels.isEmpty)

			/* Said a second after the join and still inside the window: live, so
			 the marker may follow it. */
			let live = try message(
				"@time=\(stamp(now.addingTimeInterval(1))) :bob!u@h PRIVMSG #chat :live",
				on: client
			)

			client.receivePrivmsgAndNotice(live)

			#expect(client.readMarkerPendingChannels.count == 1)
		}
	}
}
