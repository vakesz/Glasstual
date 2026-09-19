// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** A channel view that draws nothing but answers the print completion, which is
 where the unread count, the highlight badge and the notification are decided.
 The real controller supplies the rendered line number and whether the line
 highlighted; nothing here renders, so both are stated by the test. */
@MainActor
private final class CompletingPresentation: ChatItemPresenting {
	private(set) var printedLines: [ChatLine] = []
	var isHighlight = false
	var defersCompletions = false
	var isDisplayed = true
	private var completions: [@MainActor () -> Void] = []
	private var renderedDate: Date?
	/// Every date the unread divider was moved to, in order.
	private(set) var markedDates: [Date] = []
	weak var session: ServerSession?
	weak var channel: Conversation?

	let presentationIdentifier = "join-burst-presentation"

	func print(_ chatLine: ChatLine, completionBlock: PrintedLineCompletion?) {
		printedLines.append(chatLine)

		guard let completionBlock, let session else { return }

		var context = PrintedLineContext(
			session: session,
			conversation: channel,
			highlight: isHighlight,
			chatLine: chatLine,
			lineNumber: "\(printedLines.count)"
		)
		context.isDisplayed = isDisplayed
		let complete = { @MainActor [self] in
			renderedDate = max(renderedDate ?? .distantPast, chatLine.receivedAt)
			completionBlock(context)
		}
		if defersCompletions {
			completions.append(complete)
		} else {
			complete()
		}
	}

	func finishPrinting() {
		let pending = completions
		completions.removeAll()
		pending.forEach { $0() }
	}

	func lastRenderedLineDate() -> Date? {
		renderedDate
	}

	/** The real controller answers both of these from every line it has been
	 handed, rendered or not, so the stub does the same. */
	func newestConversationLineDate() -> Date? {
		printedLines.filter(\.lineType.isConversation).map(\.receivedAt).max()
	}

	func conversationLineCount(after date: Date) -> Int {
		printedLines.count { $0.lineType.isConversation && $0.receivedAt > date }
	}

	func lastPrintedLine() -> ChatLine? {
		printedLines.last
	}

	nonisolated func setTopic(_: String?) {} // nonisolated: pure
	func mark() {}
	func mark(at date: Date) {
		markedDates.append(date)
	}

	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber _: String,
		state _: ChatLineDeliveryState,
		messageIdentifier _: String?,
		reason _: String?
	) {}
	func prependEarlierChatLines(_: [ChatLine]) {}
	func tearDown(_: ChatItemTeardown) {}
}

/** The whole point of the grace period is what the user sees after a bouncer
 puts them back in a channel: the replay prints, and nothing about it counts.
 These drive the production inbound path — parse, JOIN, PRIVMSG, print, print
 completion — because the suppression only means anything if it survives every
 hop between the wire and the badge. */
@MainActor
@Suite("Post-join burst suppression", .serialized)
struct ServerSessionJoinBurstTests {
	/// Nothing here should reach the real notification centre; a test that
	/// posted one would put a banner in front of whoever ran the suite.
	private func withNotificationsSilenced(_ body: () throws -> Void) rethrows {
		let controller = AppServices.notifications
		let wasDisabled = controller.areNotificationsDisabled
		defer { controller.areNotificationsDisabled = wasDisabled }

		controller.areNotificationsDisabled = true

		try body()
	}

	private func makeSession() -> TestServerSession {
		let session = TestServerSession()
		session.linePrintObserver = nil
		session.enableCapability(.serverTime)
		session.enableCapability(.messageTags)
		session.enableCapability(.readMarker)
		session.isLoggedIn = true
		session.userNickname = "mara"

		return session
	}

	private func stamp(_ date: Date) -> String {
		DateFormatting.iso8601String(from: date)
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	/// A moment on a whole millisecond, which is all the wire stamps carry, so
	/// a date this test writes out comes back from the server's copy unchanged.
	private func whollyStampedNow() -> Date {
		Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000).rounded() / 1000)
	}

	/// Feeds numeric replies through the handler the dispatch calls, which is
	/// what prints the topic and mode lines a join is answered with.
	private func receiveNumerics(_ lines: [String], on session: TestServerSession) throws {
		for line in lines {
			try session.receiveNumericReply(message(line, on: session))
		}
	}

	/// Joins `#chat` as the local user at `joinedAt` and hands back the channel
	/// with a view attached, exactly as the production JOIN path leaves it.
	private func joinedChannel(
		on session: TestServerSession,
		at joinedAt: Date,
		drawnInto presentation: CompletingPresentation
	) throws -> Conversation {
		let join = try message("@time=\(stamp(joinedAt)) :mara!u@h JOIN #chat", on: session)

		session.receiveJoin(join)

		let channel = try #require(session.findConversation("#chat"))
		presentation.session = session
		presentation.channel = channel
		channel.presentation = presentation

		return channel
	}

	@Test("Opening and leaving a channel cannot restore its cleared badge after delayed rendering")
	func delayedPrintCannotRestoreClearedBadge() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			presentation.defersCompletions = true
			let channel = try joinedChannel(on: session, at: Date(), drawnInto: presentation)
			try session.receivePrivmsgAndNotice(message(":bob!u@h PRIVMSG #chat :hello", on: session))
			channel.resetState()
			session.markConversation(asRead: channel)
			#expect(session.readMarkers.pendingConversations.isEmpty)
			presentation.finishPrinting()
			#expect(channel.unreadCount == 0)
			#expect(session.readMarkers.pendingConversations.isEmpty)
		}
	}

	@Test("Own echoes never count, while background messages and actions count with notifications muted")
	func backgroundMessagesAndOwnEchoes() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let channel = try joinedChannel(on: session, at: Date(), drawnInto: presentation)
			session.recordedOutput.selectedConversation = channel
			session.recordedOutput.visibleItems = [channel]
			session.recordedOutput.isKeyWindow = false
			for line in [":mara!u@h PRIVMSG #chat :own", ":bob!u@h PRIVMSG #chat :hello",
			             ":bob!u@h PRIVMSG #chat :\u{1}ACTION waves\u{1}"]
			{
				try session.receivePrivmsgAndNotice(message(line, on: session))
			}
			#expect(channel.unreadCount == 2)
		}
	}

	@Test("Live messages count immediately after JOIN without server timestamps")
	func immediateLiveMessageIsUnread() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let channel = try joinedChannel(on: session, at: Date(), drawnInto: presentation)
			try session.receivePrivmsgAndNotice(message(":bob!u@h PRIVMSG #chat :hello", on: session))
			#expect(channel.unreadCount == 1)
		}
	}

	@Test("Explicit playback remains excluded after a slow replay")
	func delayedPlaybackDoesNotCount() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let channel = try joinedChannel(on: session, at: Date(), drawnInto: presentation)
			channel.activate(at: Date().addingTimeInterval(-60))
			var replay = try message(":bob!u@h PRIVMSG #chat :old message", on: session)
			replay.isReplayed = true
			session.receivePrivmsgAndNotice(replay)
			#expect(channel.unreadCount == 0)
		}
	}

	@Test("A line replayed within the grace period prints without counting as unread")
	func replayedLineInsideTheWindowIsNotUnread() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = Date()
			let channel = try joinedChannel(on: session, at: now, drawnInto: presentation)

			#expect(channel.joinedAt != nil)

			/* Stamped five seconds before the join and arriving now: said while
			 the user was away, so a bouncer is replaying it. */
			var replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :did you see this",
				on: session
			)

			replayed.isReplayed = true

			#expect(session.lineArrivedAlreadySeen(replayed, in: channel))

			replayed.isReplayed = true
			session.receivePrivmsgAndNotice(replayed)

			#expect(presentation.printedLines.last?.messageBody == "did you see this")
			#expect(channel.unreadCount == 0)
			#expect(channel.dockUnreadCount == 0)
			#expect(channel.nicknameHighlightCount == 0)
			#expect(channel.isUnread == false)
		}
	}

	@Test("A JOIN that is itself replayed opens the window from its arrival")
	func replayedJoinIsMeasuredFromArrival() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			session.znc.isConnected = true
			let presentation = CompletingPresentation()
			let now = Date()
			/* A bouncer that replays the JOIN stamps it with when it happened,
			 minutes ago; measured from that stamp the window would already be
			 shut when the burst behind it arrives. */
			let channel = try joinedChannel(on: session, at: now.addingTimeInterval(-120), drawnInto: presentation)
			let joinedAt = try #require(channel.joinedAt)

			#expect(abs(joinedAt.timeIntervalSince(now)) < 5)

			var replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :while you were out",
				on: session
			)

			replayed.isReplayed = true

			#expect(session.lineArrivedAlreadySeen(replayed, in: channel))

			replayed.isReplayed = true
			session.receivePrivmsgAndNotice(replayed)

			#expect(presentation.printedLines.last?.messageBody == "while you were out")
			#expect(channel.isUnread == false)
		}
	}

	@Test("A highlight in the replayed burst raises no badge either")
	func replayedHighlightInsideTheWindowRaisesNoBadge() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			presentation.isHighlight = true
			let now = Date()
			let channel = try joinedChannel(on: session, at: now, drawnInto: presentation)
			var replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :mara: ping",
				on: session
			)

			replayed.isReplayed = true
			session.receivePrivmsgAndNotice(replayed)

			#expect(presentation.printedLines.count == 1)
			#expect(channel.nicknameHighlightCount == 0)
			#expect(channel.unreadCount == 0)
		}
	}

	@Test("A live line said after the grace period counts as unread")
	func liveLineOutsideTheWindowIsUnread() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = Date()
			/* Joined twenty seconds ago: past the grace period, but not so far
			 back that the JOIN reads as a replayed one measured from arrival. */
			let channel = try joinedChannel(
				on: session,
				at: now.addingTimeInterval(-20),
				drawnInto: presentation
			)
			let live = try message("@time=\(stamp(now)) :bob!u@h PRIVMSG #chat :hello", on: session)

			#expect(session.lineArrivedAlreadySeen(live, in: channel) == false)

			session.receivePrivmsgAndNotice(live)

			#expect(presentation.printedLines.last?.messageBody == "hello")
			#expect(channel.unreadCount == 1)
			#expect(channel.isUnread)
		}
	}

	@Test("A line the server already reported as read stays out of the unread count")
	func lineBehindTheReadMarkerIsNotUnread() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = Date()
			let channel = try joinedChannel(
				on: session,
				at: now.addingTimeInterval(-20),
				drawnInto: presentation
			)
			let marker = try message(
				":irc.example.net MARKREAD #chat timestamp=\(stamp(now))",
				on: session
			)

			session.receiveReadMarker(marker)

			#expect(session.readMarkers.sentDates[channel.uniqueIdentifier] != nil)

			let behindTheMarker = try message(
				"@time=\(stamp(now.addingTimeInterval(-1))) :bob!u@h PRIVMSG #chat :old news",
				on: session
			)

			session.receivePrivmsgAndNotice(behindTheMarker)

			#expect(presentation.printedLines.last?.messageBody == "old news")
			#expect(channel.unreadCount == 0)
		}
	}

	@Test("The replay does not push the server's read marker past what the user has seen")
	func replayedLinesDoNotAdvanceTheReadMarker() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = Date()
			let channel = try joinedChannel(on: session, at: now, drawnInto: presentation)
			/* Visible in the key window but not selected, which is the state that
			 otherwise marks every printed line as read. */
			session.recordedOutput.isKeyWindow = true
			session.recordedOutput.visibleItems = [channel]

			var replayed = try message(
				"@time=\(stamp(now.addingTimeInterval(-5))) :bob!u@h PRIVMSG #chat :replayed",
				on: session
			)

			replayed.isReplayed = true
			session.receivePrivmsgAndNotice(replayed)

			#expect(session.readMarkers.pendingConversations.isEmpty)

			/* Said a second after the join and still inside the window: live, so
			 the marker may follow it. */
			let live = try message(
				"@time=\(stamp(now.addingTimeInterval(1))) :bob!u@h PRIVMSG #chat :live",
				on: session
			)

			session.receivePrivmsgAndNotice(live)

			#expect(session.readMarkers.pendingConversations.count == 1)
		}
	}

	@Test("A read marker from before the join raises no badge for the burst the join printed")
	func readMarkerOlderThanTheJoinBurstRaisesNoBadge() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = whollyStampedNow()
			let channel = try joinedChannel(on: session, at: now, drawnInto: presentation)

			/* The topic, who set it and the channel modes: everything a join is
			 answered with, printed now and none of it anything a person said. */
			try receiveNumerics([
				":irc.example.net 332 mara #chat :the topic",
				":irc.example.net 333 mara #chat bob!u@h 1700000000",
				":irc.example.net 324 mara #chat +nt",
			], on: session)

			let printedTypes = presentation.printedLines.map(\.lineType)

			#expect(printedTypes.contains(.topic))
			#expect(printedTypes.contains(.mode))
			#expect(printedTypes.allSatisfy { $0.isConversation == false })

			let marker = try message(
				":irc.example.net MARKREAD #chat timestamp=\(stamp(now.addingTimeInterval(-3600)))",
				on: session
			)

			session.receiveReadMarker(marker)

			#expect(channel.unreadCount == 0)
			#expect(channel.dockUnreadCount == 0)
			#expect(channel.isUnread == false)
			#expect(presentation.markedDates.isEmpty)
		}
	}

	@Test("A read marker behind a replayed burst counts the messages past it and nothing else")
	func readMarkerBehindReplayedMessagesRaisesCountedBadge() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = whollyStampedNow()
			let channel = try joinedChannel(on: session, at: now, drawnInto: presentation)
			let markerDate = now.addingTimeInterval(-30)

			for line in [
				"@time=\(stamp(now.addingTimeInterval(-20))) :bob!u@h PRIVMSG #chat :first",
				"@time=\(stamp(now.addingTimeInterval(-10))) :bob!u@h PRIVMSG #chat :second",
			] {
				var replayed = try message(line, on: session)
				replayed.isReplayed = true
				session.receivePrivmsgAndNotice(replayed)
			}

			/* Printed after both messages and newer than the marker, so counting
			 lines of any kind would report three unread instead of two. */
			try receiveNumerics([":irc.example.net 332 mara #chat :the topic"], on: session)

			#expect(channel.unreadCount == 0)

			let marker = try message(
				":irc.example.net MARKREAD #chat timestamp=\(stamp(markerDate))",
				on: session
			)

			session.receiveReadMarker(marker)

			#expect(presentation.markedDates.count == 1)
			#expect(abs((presentation.markedDates.first ?? .distantPast).timeIntervalSince(markerDate)) < 0.002)
			#expect(channel.unreadCount == 2)
		}
	}

	/** The `MARKREAD` reply arrives in the same turn as the burst it refers to,
	 while the lines are still rendering. Answering it from the view alone would
	 find nothing past the marker and leave the burst unbadged. */
	@Test("A read marker behind a burst that has not rendered yet still raises its badge")
	func readMarkerBehindUnrenderedReplayRaisesCountedBadge() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = whollyStampedNow()
			let channel = try joinedChannel(on: session, at: now, drawnInto: presentation)
			let markerDate = now.addingTimeInterval(-30)

			presentation.defersCompletions = true

			for line in [
				"@time=\(stamp(now.addingTimeInterval(-20))) :bob!u@h PRIVMSG #chat :first",
				"@time=\(stamp(now.addingTimeInterval(-10))) :bob!u@h PRIVMSG #chat :second",
			] {
				var replayed = try message(line, on: session)
				replayed.isReplayed = true
				session.receivePrivmsgAndNotice(replayed)
			}

			let marker = try message(
				":irc.example.net MARKREAD #chat timestamp=\(stamp(markerDate))",
				on: session
			)

			session.receiveReadMarker(marker)

			#expect(presentation.markedDates.count == 1)
			#expect(channel.unreadCount == 2)

			/* The burst finishes rendering afterwards, and being a replay it still
			 counts for nothing: the badge the marker raised is what is left. */
			presentation.finishPrinting()

			#expect(channel.unreadCount == 2)
		}
	}

	@Test("A read marker past the last message clears the badge a later topic cannot hold open")
	func readMarkerPastTheLastMessageClearsBadgeDespiteLaterTopic() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			let now = whollyStampedNow()
			/* Joined twenty seconds ago, so the message below is live and counts. */
			let channel = try joinedChannel(on: session, at: now.addingTimeInterval(-20), drawnInto: presentation)

			try session.receivePrivmsgAndNotice(
				message("@time=\(stamp(now)) :bob!u@h PRIVMSG #chat :hello", on: session)
			)

			#expect(channel.unreadCount == 1)

			try receiveNumerics([
				"@time=\(stamp(now.addingTimeInterval(20))) :irc.example.net 332 mara #chat :the topic",
			], on: session)

			let marker = try message(
				":irc.example.net MARKREAD #chat timestamp=\(stamp(now.addingTimeInterval(10)))",
				on: session
			)

			session.receiveReadMarker(marker)

			#expect(channel.unreadCount == 0)
			#expect(channel.dockUnreadCount == 0)
			#expect(channel.isUnread == false)
		}
	}

	@Test("Rendering into a pending view cannot acknowledge the message")
	func bufferedLineCannotAdvanceReadMarker() throws {
		try withNotificationsSilenced {
			let session = makeSession()
			let presentation = CompletingPresentation()
			presentation.isDisplayed = false
			let channel = try joinedChannel(on: session, at: Date(), drawnInto: presentation)
			session.recordedOutput.isKeyWindow = true
			session.recordedOutput.visibleItems = [channel]
			try session.receivePrivmsgAndNotice(message(":bob!u@h PRIVMSG #chat :still loading", on: session))
			#expect(session.readMarkers.pendingConversations.isEmpty)
		}
	}
}
