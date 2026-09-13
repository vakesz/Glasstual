/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

/** A spoken notification used to be built by appending a label, " in %@",
 " by %@" and ", " to each other, so a translator was handed four fragments in
 English word order and no way to reorder or inflect them. Each shape is one
 entry now, and which shape is used follows from what the person asked to hear.
 These pin the four shapes per event, because a missing entry is a sentence
 that silently loses a word. */
@Suite("Spoken notification copy")
struct SpokenNotificationCopyTests {
	@Test("A channel event names whichever of the channel and the author was asked for")
	func channelEventShapes() {
		let spoken = NotificationStrings.Spoken.self

		#expect(
			spoken.channelEvent(.channelMessage, channelName: "#textual", nickname: "alice", text: "hello")
				== "Channel Message in #textual by alice, hello"
		)
		#expect(
			spoken.channelEvent(.channelMessage, channelName: "#textual", nickname: nil, text: "hello")
				== "Channel Message in #textual, hello"
		)
		#expect(
			spoken.channelEvent(.channelMessage, channelName: nil, nickname: "alice", text: "hello")
				== "Channel Message by alice, hello"
		)
		#expect(
			spoken.channelEvent(.channelNotice, channelName: "#textual", nickname: "alice", text: "hello")
				== "Channel Notice in #textual by alice, hello"
		)
		#expect(
			spoken.channelEvent(.highlight, channelName: "#textual", nickname: "alice", text: "hello")
				== "Highlight in #textual by alice, hello"
		)
		#expect(
			spoken.channelEvent(.highlight, channelName: nil, nickname: "alice", text: "hello")
				== "Highlight by alice, hello"
		)
	}

	/// Asked for neither the channel nor the author, the sentence is the
	/// message: nothing is prefixed, so nothing has to be translated.
	@Test("With nothing to name, only the message is spoken")
	func barestShapeIsTheMessageItself() {
		#expect(
			NotificationStrings.Spoken.channelEvent(
				.channelMessage,
				channelName: nil,
				nickname: nil,
				text: "hello"
			) == "hello"
		)
	}

	/// A private message has no channel to name, so its highlight always says
	/// who it came from.
	@Test("A highlight in a private message names the sender")
	func privateHighlightNamesTheSender() {
		#expect(
			NotificationStrings.Spoken.privateHighlight(from: "alice", text: "hello")
				== "Highlight in Private Message from alice, hello"
		)
	}
}
