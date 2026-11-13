// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** When the transcript builds the profile presentation for a line's header.

 Building it compares display names against every member of the channel, and
 the cache is keyed on the member list, so during a join burst every changed
 list rebuilt it for each line drawn. A sender with no profile has nothing to
 draw, so their line builds nothing. */
@MainActor
@Suite("Transcript controller sender profiles")
struct TranscriptControllerSenderProfileTests {
	@Test("A line from a sender without a profile builds no presentation")
	func senderWithoutProfileBuildsNothing() throws {
		let session = try makeMetadataSession()
		try withController(on: session) { controller in
			#expect(controller.senderProfile(for: "peer") == nil)
			#expect(controller.senderPresentation == nil)
		}
	}

	@Test("A sender with a profile is drawn with it")
	func senderWithProfileIsDrawn() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		try withController(on: session) { controller in
			#expect(controller.senderProfile(for: "peer")?.displayName == "Peer Display")
			#expect(controller.senderPresentation != nil)
		}
	}

	@Test("Profiles switched off build no presentation even for a sender who set one")
	func profilesSwitchedOffBuildNothing() throws {
		let session = try makeMetadataSession()
		try session.receive(":irc.example.net METADATA peer display-name * :Peer Display")
		session.environment.settings.showsServerProfiles = false
		try withController(on: session) { controller in
			#expect(controller.senderProfile(for: "peer") == nil)
			#expect(controller.senderPresentation == nil)
		}
	}

	private func withController(on session: ServerSession, _ body: (TranscriptController) throws -> Void) throws {
		let channel = try #require(session.findConversation("#c"))
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		let controller = TranscriptController(conversation: channel, in: window)
		try body(controller)
	}
}
