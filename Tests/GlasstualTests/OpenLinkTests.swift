/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** What `OpenLink` does with a URL a stranger put in a channel.

 The scheme allowlist is the only thing between that string and an app launch
 on this machine, so both directions of the guard are asserted here: a refused
 scheme reaches no opener at all, and a permitted one reaches it once with the
 background flag the caller asked for. The opens are recorded rather than
 performed — the point of the seam is that the suite never asks the real
 workspace to open `file:///etc/passwd` to find out what it would do. */
@MainActor
@Suite("Opening a link")
struct OpenLinkTests {
	private struct Opened: Equatable {
		let url: URL
		let inBackground: Bool
	}

	private final class Recorder {
		var opens: [Opened] = []
	}

	/// Runs `body` with a recording opener in place and returns what it saw.
	/// The workspace opener is restored even when `body` throws.
	private func opens(during body: () throws -> Void) rethrows -> [Opened] {
		let recorder = Recorder()

		OpenLink.opener = { url, inBackground in
			recorder.opens.append(Opened(url: url, inBackground: inBackground))
		}

		defer { OpenLink.opener = OpenLink.workspaceOpener }

		try body()

		return recorder.opens
	}

	@Test(
		"A scheme the allowlist refuses never reaches the opener",
		arguments: [
			"file:///etc/passwd",
			"smb://example.org/share",
			"afp://example.org/share",
			"nfs://example.org/export",
			"cifs://example.org/share",
			"x-apple.systempreferences:com.apple.preference.security",
			"javascript:alert(1)",
			"data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
		]
	)
	func refusedSchemesNeverOpen(string: String) throws {
		let url = try #require(URL(string: string))

		#expect(opens { OpenLink.open(url: url) }.isEmpty)
		#expect(opens { OpenLink.open(string: string) }.isEmpty)
	}

	/// A denied scheme stays denied however permissive the user's allowlist is:
	/// `LinkParser` refuses those before it consults a preference at all.
	@Test("The user allowlist cannot re-enable a denied scheme")
	func permittingEverythingStillRefusesTheDeniedSchemes() throws {
		let key = Preferences.LinkSchemes.permitAny
		let original = key.storedValue

		defer { key.storedValue = original }

		key.value = true

		let url = try #require(URL(string: "file:///etc/passwd"))

		#expect(opens { OpenLink.open(url: url) }.isEmpty)
	}

	@Test(
		"A permitted scheme reaches the opener once",
		arguments: [
			"https://example.org/page",
			"http://example.org/page",
			"irc://irc.example.org/#channel",
			"ircs://irc.example.org/#channel",
		]
	)
	func permittedSchemesOpenOnce(string: String) throws {
		let url = try #require(URL(string: string))

		#expect(opens { OpenLink.open(url: url, inBackground: false) } == [Opened(url: url, inBackground: false)])
	}

	/// `openBrowserInBackground` is the caller's, not the opener's, decision:
	/// whatever `open(url:inBackground:)` was told is what arrives.
	@Test("The background flag arrives as the caller passed it", arguments: [true, false])
	func theBackgroundFlagIsCarriedThrough(inBackground: Bool) throws {
		let url = try #require(URL(string: "https://example.org/page"))

		#expect(
			opens { OpenLink.open(url: url, inBackground: inBackground) }
				== [Opened(url: url, inBackground: inBackground)]
		)
		#expect(
			opens { OpenLink.open(string: "https://example.org/page", inBackground: inBackground) }
				== [Opened(url: url, inBackground: inBackground)]
		)
	}

	/** A scheme no list mentions is refused, and the user's own list is what
	 changes that. The keys keep the names the AutoHyperlinks parser used, so
	 this is also the path a preferences file carried over from Textual takes. */
	@Test("A scheme the user permitted is opened")
	func theUserAllowlistIsHonoured() throws {
		let key = Preferences.LinkSchemes.permitted
		let original = key.storedValue

		defer { key.storedValue = original }

		let url = try #require(URL(string: "x-glasstual-test://open"))

		key.value = []
		#expect(opens { OpenLink.open(url: url) }.isEmpty)

		key.value = ["x-glasstual-test"]
		#expect(opens { OpenLink.open(url: url, inBackground: false) } == [Opened(url: url, inBackground: false)])
	}

	/// A scheme dropped from the shipped default list stops being opened, which
	/// is what makes that list a policy rather than a note.
	@Test("Removing a scheme from the default list stops it being opened")
	func theDefaultAllowlistIsHonoured() throws {
		let key = Preferences.LinkSchemes.permittedDefault
		let original = key.storedValue

		defer { key.storedValue = original }

		let url = try #require(URL(string: "irc://irc.example.org/#channel"))

		key.value = key.defaultValue.filter { $0 != "irc" }

		#expect(opens { OpenLink.open(url: url) }.isEmpty)
	}

	@Test("A string that is not a URL opens nothing")
	func aStringThatIsNotAURLOpensNothing() {
		#expect(opens { OpenLink.open(string: "") }.isEmpty)
	}
}
