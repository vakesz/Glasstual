// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Pasted text goes out as one `draft/multiline` batch when the server offers
/// it, the text fits, and the person says so.
@MainActor
@Suite("Multi-line sending")
struct ServerSessionMultilineSendingTests {
	private func session(limits: [String] = ["max-bytes=4096", "max-lines=10"], negotiated: Bool = true) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userNickname = "me"
		session.identity.hostmask = "me!user@example.org"
		session.markAsLoggedIn()
		if negotiated {
			session.enableCapability(.batch)
			session.enableCapability(.messageTags)
			session.enableCapability(.multiline)
			session.capabilityNegotiation.offer(MultilineLimits.capabilityName, values: limits)
		}
		return session
	}

	private func channel(on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate("#chan"))
		channel.activate()
		return channel
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}

	private func drain(_ session: ServerSession) async {
		let deadline = ContinuousClock.now + .seconds(5)
		while session.outboundTextProducer?.pendingProducerCount ?? 0 != 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
	}

	/// The reference the opening line chose, read back off the wire.
	private func batchReference(in lines: [String]) throws -> String {
		let opening = try #require(lines.first { $0.contains("BATCH +") })
		let start = try #require(opening.range(of: "BATCH +"))
		return try String(#require(opening[start.upperBound...].split(separator: " ").first))
	}

	@Test("Text of several lines becomes a proposal while the capability is on")
	func proposalForPastedLines() throws {
		let session = session()
		let channel = try channel(on: session)

		let proposal = try #require(session.multilineProposal(
			for: NSAttributedString(string: "one\ntwo\nthree"),
			as: .privmsg,
			in: channel
		))

		#expect(proposal.lines.map(\.text) == ["one", "two", "three"])
		#expect(proposal.fit == .fits)
	}

	@Test("Without the capability there is no proposal")
	func noProposalWithoutTheCapability() throws {
		let session = session(negotiated: false)
		let channel = try channel(on: session)

		#expect(session.multilineProposal(for: NSAttributedString(string: "one\ntwo"), as: .privmsg, in: channel) == nil)
	}

	@Test("A capability value without a byte limit is not used")
	func noProposalWithoutAByteLimit() throws {
		let session = session(limits: ["max-lines=5"])
		let channel = try channel(on: session)

		#expect(session.multilineLimits == nil)
		#expect(session.multilineProposal(for: NSAttributedString(string: "one\ntwo"), as: .privmsg, in: channel) == nil)
	}

	@Test("The capability is not used until its dependencies are in force")
	func dependenciesAreRequired() {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.enableCapability(.multiline)
		session.capabilityNegotiation.offer(MultilineLimits.capabilityName, values: ["max-bytes=4096"])

		#expect(session.multilineLimits == nil)
	}

	@Test("Text that is not a plain multi-line message gets no proposal", arguments: [
		"just one line",
		"one\n/me waves",
		"/join #elsewhere\nsecond",
		"\n\none line between blanks\n\n",
	])
	func notEligible(_ text: String) throws {
		let session = session()
		let channel = try channel(on: session)

		#expect(session.multilineProposal(for: NSAttributedString(string: text), as: .privmsg, in: channel) == nil)
	}

	@Test("An action is never sent as a batch")
	func noProposalForAnAction() throws {
		let session = session()
		let channel = try channel(on: session)

		#expect(session.multilineProposal(for: NSAttributedString(string: "one\ntwo"), as: .privmsgAction, in: channel) == nil)
	}

	@Test("A doubled slash sends the line with one slash")
	func doubledSlashIsEscaped() throws {
		let session = session()
		let channel = try channel(on: session)

		let proposal = try #require(session.multilineProposal(for: NSAttributedString(string: "//path\ntext"), as: .privmsg, in: channel))

		#expect(proposal.lines.map(\.text) == ["/path", "text"])
	}

	@Test("A blank line between two lines is kept")
	func blankLineStays() throws {
		let session = session()
		let channel = try channel(on: session)

		let proposal = try #require(session.multilineProposal(for: NSAttributedString(string: "one\n\ntwo\n"), as: .privmsg, in: channel))

		#expect(proposal.lines.map(\.text) == ["one", "", "two"])
	}

	@Test("A line longer than the wire allows is cut into continuation lines")
	func longLineIsCut() throws {
		let session = session(limits: ["max-bytes=100000"])
		let channel = try channel(on: session)
		let long = String(repeating: "a", count: 1200)

		let proposal = try #require(session.multilineProposal(for: NSAttributedString(string: "\(long)\nshort"), as: .privmsg, in: channel))

		let flags = proposal.lines.map(\.continuesPrevious)
		#expect(flags.first == false)
		let middleContinues = flags.dropFirst().dropLast().allSatisfy(\.self)
		#expect(middleContinues)
		#expect(flags.last == false)
		#expect(proposal.lines.count >= 4)
		#expect(MultilineBatchPlanner.joinedText(of: proposal.lines) == "\(long)\nshort")
	}

	@Test("Text over the line limit is reported and its first part fits")
	func overTheLineLimit() throws {
		let session = session(limits: ["max-bytes=4096", "max-lines=2"])
		let channel = try channel(on: session)

		let proposal = try #require(session.multilineProposal(for: NSAttributedString(string: "a\nb\nc"), as: .privmsg, in: channel))

		#expect(proposal.fit == .tooManyLines)
		#expect(proposal.firstPart.map(\.text) == ["a", "b"])
	}

	@Test("Pasting asks how to send, and sends nothing until answered")
	func pasteAsksFirst() throws {
		let session = session()
		let channel = try channel(on: session)

		session.inputText("one\ntwo", destination: channel)

		let alert = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(session.recordedOutput.presentedAlerts.count == 1)
		#expect(alert.defaultButton == String(localized: .MultilineSending.sendAsOneButton))
		#expect(alert.alternateButton == String(localized: .MultilineSending.sendLineByLineButton))
		#expect(alert.otherButton != nil)
		#expect(alert.cancelButton == .other)
		#expect(sentLines(of: session).isEmpty)
	}

	@Test("Text over the limits asks to truncate instead")
	func overLimitAsksToTruncate() throws {
		let session = session(limits: ["max-bytes=4096", "max-lines=2"])
		let channel = try channel(on: session)

		session.inputText("a\nb\nc", destination: channel)

		let alert = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(alert.defaultButton == String(localized: .MultilineSending.truncateAndSendButton))
		#expect(alert.style == .warning)
	}

	@Test("Without the capability a paste goes line by line as before")
	func pasteWithoutTheCapability() async throws {
		let session = session(negotiated: false)
		let channel = try channel(on: session)

		session.inputText("one\ntwo", destination: channel)
		await drain(session)

		#expect(session.recordedOutput.presentedAlerts.isEmpty)
		#expect(sentLines(of: session) == ["PRIVMSG #chan :one", "PRIVMSG #chan :two"])
	}

	@Test("Choosing one message writes one batch around the lines")
	func sendsOneBatch() async throws {
		let session = session()
		let channel = try channel(on: session)
		let proposal = try #require(session.multilineProposal(for: NSAttributedString(string: "one\ntwo"), as: .privmsg, in: channel))

		session.carryOutMultilineChoice(
			.sendAsOneMessage,
			proposal: proposal,
			text: NSAttributedString(string: "one\ntwo"),
			as: .privmsg,
			in: channel,
			replyIdentifier: nil
		)
		await drain(session)

		let lines = sentLines(of: session)
		let reference = try batchReference(in: lines)
		#expect(lines == [
			"BATCH +\(reference) draft/multiline #chan",
			"@batch=\(reference) PRIVMSG #chan :one",
			"@batch=\(reference) PRIVMSG #chan :two",
			"BATCH -\(reference)",
		])
	}

	@Test("A continuation line carries the concat tag")
	func continuationCarriesTheTag() async throws {
		let session = session(limits: ["max-bytes=100000"])
		let channel = try channel(on: session)
		let text = NSAttributedString(string: String(repeating: "a", count: 1200) + "\nend")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))

		session.carryOutMultilineChoice(.sendAsOneMessage, proposal: proposal, text: text, as: .privmsg, in: channel, replyIdentifier: nil)
		await drain(session)

		let lines = sentLines(of: session)
		let reference = try batchReference(in: lines)
		let continuation = "@batch=\(reference);draft/multiline-concat PRIVMSG #chan :"
		#expect(lines.filter { $0.hasPrefix(continuation) }.count == proposal.lines.filter(\.continuesPrevious).count)
		#expect(lines.filter { $0.contains("multiline-concat") }.isEmpty == false)
	}

	@Test("The message is printed once, as the whole text")
	func printsTheWholeTextOnce() async throws {
		let session = session()
		let channel = try channel(on: session)
		let text = NSAttributedString(string: "one\ntwo")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))
		let printedBefore = session.printedLines.count

		session.carryOutMultilineChoice(.sendAsOneMessage, proposal: proposal, text: text, as: .privmsg, in: channel, replyIdentifier: nil)
		await drain(session)

		let printed = session.printedLines.compactMap { $0 as? [String: Any] }.dropFirst(printedBefore)
		#expect(printed.count == 1)
		#expect(printed.first?["messageBody"] as? String == "one\ntwo")
	}

	@Test("With echo-message the echo is what prints")
	func echoPrintsInstead() async throws {
		let session = session()
		session.enableCapability(.echoMessage)
		let channel = try channel(on: session)
		let text = NSAttributedString(string: "one\ntwo")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))
		let printedBefore = session.printedLines.count

		session.carryOutMultilineChoice(.sendAsOneMessage, proposal: proposal, text: text, as: .privmsg, in: channel, replyIdentifier: nil)
		await drain(session)

		#expect(session.printedLines.count == printedBefore)
		#expect(sentLines(of: session).count == 4)
	}

	@Test("A label and a reply go on the opening line")
	func labelAndReplyGoOnTheOpeningLine() async throws {
		let session = session()
		session.enableCapability(.labeledResponse)
		let channel = try channel(on: session)
		let text = NSAttributedString(string: "one\ntwo")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))

		session.carryOutMultilineChoice(
			.sendAsOneMessage,
			proposal: proposal,
			text: text,
			as: .privmsg,
			in: channel,
			replyIdentifier: "abc123"
		)
		await drain(session)

		let opening = try #require(sentLines(of: session).first)
		#expect(opening.hasPrefix("@+draft/reply=abc123;label=g1 BATCH +ml"))
		#expect(sentLines(of: session).dropFirst().allSatisfy { $0.hasPrefix("@batch=") || $0.hasPrefix("BATCH -") })
	}

	@Test("Choosing line by line sends one message per line")
	func lineByLine() async throws {
		let session = session()
		let channel = try channel(on: session)
		let text = NSAttributedString(string: "one\ntwo")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))

		session.carryOutMultilineChoice(.sendLineByLine, proposal: proposal, text: text, as: .privmsg, in: channel, replyIdentifier: nil)
		await drain(session)

		#expect(sentLines(of: session) == ["PRIVMSG #chan :one", "PRIVMSG #chan :two"])
	}

	@Test("Choosing the first part sends only what fits")
	func firstPart() async throws {
		let session = session(limits: ["max-bytes=4096", "max-lines=2"])
		let channel = try channel(on: session)
		let text = NSAttributedString(string: "a\nb\nc")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))

		session.carryOutMultilineChoice(.sendFirstPart, proposal: proposal, text: text, as: .privmsg, in: channel, replyIdentifier: nil)
		await drain(session)

		let lines = sentLines(of: session)
		#expect(lines.count == 4)
		#expect(lines.contains { $0.hasSuffix("PRIVMSG #chan :a") })
		#expect(lines.contains { $0.hasSuffix("PRIVMSG #chan :b") })
		#expect(lines.contains { $0.hasSuffix("PRIVMSG #chan :c") } == false)
	}

	@Test("Cancelling sends nothing")
	func cancelling() async throws {
		let session = session()
		let channel = try channel(on: session)
		let text = NSAttributedString(string: "one\ntwo")
		let proposal = try #require(session.multilineProposal(for: text, as: .privmsg, in: channel))

		session.carryOutMultilineChoice(.cancel, proposal: proposal, text: text, as: .privmsg, in: channel, replyIdentifier: nil)
		await drain(session)

		#expect(sentLines(of: session).isEmpty)
	}

	@Test("Each button stands for one decision", arguments: [
		MultilineBatchPlanner.Fit.fits,
		MultilineBatchPlanner.Fit.tooManyLines,
		MultilineBatchPlanner.Fit.tooManyBytes,
	])
	func buttonsMapToChoices(_ fit: MultilineBatchPlanner.Fit) {
		let first: MultilineChoice = fit == .fits ? .sendAsOneMessage : .sendFirstPart

		#expect(MultilineChoice(response: .default, fit: fit) == first)
		#expect(MultilineChoice(response: .alternate, fit: fit) == .sendLineByLine)
		#expect(MultilineChoice(response: .other, fit: fit) == .cancel)
		#expect(MultilineChoice(unattended: fit) == (fit == .fits ? .sendAsOneMessage : .sendLineByLine))
	}
}
