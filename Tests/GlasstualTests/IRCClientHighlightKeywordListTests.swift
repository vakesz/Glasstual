/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Keeps the lines a channel was asked to draw, so that a test can read the
/// keyword lists the client attached to them.
@MainActor
private final class RecordingChannelPresentation: TreeItemPresentation {
	private(set) var printedLines: [LogLine] = []

	nonisolated let presentationIdentifier = "recording-presentation" // nonisolated: let

	/** The completion block reports the rendered line number, which only the
	 real controller can supply; no caller here passes one. */
	func print(_ logLine: LogLine, completionBlock _: LogControllerPrintOperationCompletion?) {
		printedLines.append(logLine)
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

/** The two lists a printed line is matched against are assembled per line, out
 of three sources: the global keyword lists, the local nickname, and the
 per-server highlight rules. Which of them apply is a decision, and getting it
 wrong is silent — the user simply stops being highlighted.

 The lists are read off the line the channel was handed, which is where they
 are actually used, rather than off the assembler; the client's own print
 observer is cleared so that the production path runs to the end. */
@MainActor
@Suite("Highlight keyword lists")
struct IRCClientHighlightKeywordListTests {
	private func client(
		matchKeywords: [String] = [],
		excludeKeywords: [String] = [],
		highlightCurrentNickname: Bool = false,
		matchingMethod: NicknameHighlightMatchMode = .partial
	) -> GLTTestClient {
		var preferences = ClientPreferences()
		preferences.highlightMatchKeywords = matchKeywords
		preferences.highlightExcludeKeywords = excludeKeywords
		preferences.highlightCurrentNickname = highlightCurrentNickname
		preferences.highlightMatchingMethod = matchingMethod

		let client = GLTTestClient(
			configDictionary: [:],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
		client.linePrintObserver = nil
		client.userNickname = "mara"

		return client
	}

	private func channel(
		named name: String,
		on client: GLTTestClient,
		drawnInto presentation: RecordingChannelPresentation
	) throws -> IRCChannel {
		let channel = try #require(client.findChannelOrCreate(name))
		channel.presentation = presentation

		return channel
	}

	/// The lists as they reached the channel, for a line said by someone else.
	private func keywordLists(
		fromRemoteMessageIn channel: IRCChannel,
		on client: GLTTestClient,
		drawnInto presentation: RecordingChannelPresentation
	) throws -> (exclude: [String]?, match: [String]?) {
		client.print(
			"hello",
			by: "someone",
			in: channel,
			as: .privateMessage,
			command: "PRIVMSG",
			receivedAt: Date(),
			isEncrypted: false
		)

		let line = try #require(presentation.printedLines.last)

		return (line.excludeKeywords, line.highlightKeywords)
	}

	@Test("The global lists are what a line is matched against by default")
	func globalListsAreCarried() throws {
		let client = client(matchKeywords: ["alpha"], excludeKeywords: ["beta"])
		let presentation = RecordingChannelPresentation()
		let channel = try channel(named: "#chat", on: client, drawnInto: presentation)

		let lists = try keywordLists(fromRemoteMessageIn: channel, on: client, drawnInto: presentation)

		#expect(lists.match == ["alpha"])
		#expect(lists.exclude == ["beta"])
	}

	/// A line the user said, and a channel set to ignore highlights, are drawn
	/// with no lists at all rather than with empty ones.
	@Test("A line the policy excludes from matching gets no lists at all")
	func disallowedLinesGetNoLists() throws {
		let client = client(matchKeywords: ["alpha"], excludeKeywords: ["beta"])
		let presentation = RecordingChannelPresentation()
		let channel = try channel(named: "#chat", on: client, drawnInto: presentation)

		client.print(
			"hello",
			by: "mara",
			in: channel,
			as: .privateMessage,
			command: "PRIVMSG",
			receivedAt: Date(),
			isEncrypted: false
		)

		let ownLine = try #require(presentation.printedLines.last)

		#expect(ownLine.memberType == .localUser)
		#expect(ownLine.highlightKeywords == nil)
		#expect(ownLine.excludeKeywords == nil)

		var ignoringConfig = channel.config
		ignoringConfig.ignoreHighlights = true
		channel.updateConfig(ignoringConfig)

		let ignored = try keywordLists(fromRemoteMessageIn: channel, on: client, drawnInto: presentation)

		#expect(ignored.match == nil)
		#expect(ignored.exclude == nil)
	}

	/** "Highlight my nickname" is a match keyword the user never typed. It is
	 withheld from a regular-expression list, where a bare nickname would be a
	 pattern rather than a word and could not be escaped by the user. */
	@Test("The local nickname joins the match list unless the method is a regular expression")
	func localNicknameIsAppendedExceptForRegularExpressions() throws {
		let partial = client(matchKeywords: ["alpha"], highlightCurrentNickname: true)
		let partialPresentation = RecordingChannelPresentation()
		let partialChannel = try channel(named: "#chat", on: partial, drawnInto: partialPresentation)

		#expect(
			try keywordLists(fromRemoteMessageIn: partialChannel, on: partial, drawnInto: partialPresentation)
				.match == ["alpha", "mara"]
		)

		let regular = client(
			matchKeywords: ["alpha"],
			highlightCurrentNickname: true,
			matchingMethod: .regularExpression
		)
		let regularPresentation = RecordingChannelPresentation()
		let regularChannel = try channel(named: "#chat", on: regular, drawnInto: regularPresentation)

		#expect(
			try keywordLists(fromRemoteMessageIn: regularChannel, on: regular, drawnInto: regularPresentation)
				.match == ["alpha"]
		)
	}

	@Test("The nickname is not added twice when it is already a keyword")
	func localNicknameIsAppendedOnlyOnce() throws {
		let client = client(matchKeywords: ["mara"], highlightCurrentNickname: true)
		let presentation = RecordingChannelPresentation()
		let channel = try channel(named: "#chat", on: client, drawnInto: presentation)

		#expect(
			try keywordLists(fromRemoteMessageIn: channel, on: client, drawnInto: presentation)
				.match == ["mara"]
		)
	}

	@Test("A per-server rule joins the match or the exclude list, by its own flag")
	func serverRulesJoinTheListTheirFlagNames() throws {
		let client = client(matchKeywords: ["alpha"], excludeKeywords: ["beta"])
		let presentation = RecordingChannelPresentation()
		let channel = try channel(named: "#chat", on: client, drawnInto: presentation)

		client.config.highlightList = [
			HighlightMatchCondition(matchKeyword: "included"),
			HighlightMatchCondition(matchKeyword: "omitted", matchIsExcluded: true),
		]

		let lists = try keywordLists(fromRemoteMessageIn: channel, on: client, drawnInto: presentation)

		#expect(lists.match == ["alpha", "included"])
		#expect(lists.exclude == ["beta", "omitted"])
	}

	/** A rule scoped to one channel must not follow the user into another, and
	 a rule with no channel — the empty identifier an unscoped row carries —
	 applies everywhere. */
	@Test("A rule scoped to another channel is skipped, and an unscoped rule is not")
	func channelScopedRulesApplyOnlyToTheirChannel() throws {
		let client = client()
		let chatPresentation = RecordingChannelPresentation()
		let otherPresentation = RecordingChannelPresentation()
		let chat = try channel(named: "#chat", on: client, drawnInto: chatPresentation)
		let other = try channel(named: "#other", on: client, drawnInto: otherPresentation)

		client.config.highlightList = [
			HighlightMatchCondition(matchKeyword: "everywhere", matchChannelId: ""),
			HighlightMatchCondition(matchKeyword: "chat-only", matchChannelId: chat.uniqueIdentifier),
			HighlightMatchCondition(matchKeyword: "other-only", matchChannelId: other.uniqueIdentifier),
		]

		#expect(
			try keywordLists(fromRemoteMessageIn: chat, on: client, drawnInto: chatPresentation)
				.match == ["everywhere", "chat-only"]
		)
		#expect(
			try keywordLists(fromRemoteMessageIn: other, on: client, drawnInto: otherPresentation)
				.match == ["everywhere", "other-only"]
		)
	}
}
