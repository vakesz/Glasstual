/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** The two themes Glasstual ships, rendering one fixed line.

 A theme is markup a third party writes a stylesheet against, and most of that
 markup comes from templates the application supplies rather than the theme.
 Nothing pinned it: a renamed class, a dropped data attribute or a partial that
 stopped resolving would leave every test passing and every third-party
 stylesheet written against the old markup broken.

 So one line, with the same attributes, is rendered through each theme's own
 template repositories and compared against what it produces today, and each
 theme's one overridden template is pinned beside it. */
@Suite("Bundled theme rendering")
nonisolated struct BundledThemeRenderTests {
	nonisolated struct BundledTheme: Sendable, CustomStringConvertible {
		let name: String
		let variety: String

		/// A private message from `alice`, encrypted, rendered by this theme.
		let expectedLine: String

		/// The one template both bundled themes carry of their own.
		let expectedLock: String

		var description: String {
			"\(name) (\(variety))"
		}

		static let all: [Self] = [
			Self(
				name: "Bubbles",
				variety: "Light",
				expectedLine: expectedSharedLine,
				expectedLock: expectedDarkIconLock
			),
			Self(
				name: "Lines",
				variety: "Light",
				expectedLine: expectedSharedLine,
				expectedLock: expectedDarkIconLock
			),
		]
	}

	@Test("A fixed line renders to the same HTML it always has", arguments: BundledTheme.all)
	func fixedLineRendersToItsPinnedFragment(theme: BundledTheme) throws {
		var cache = ThemeTemplateCache(sources: Self.templateSources(for: theme))
		let compiled = cache.template(named: "newMessagePostedWithSender")

		let template = try #require(
			compiled,
			"\(theme) resolves no template for a message with a sender"
		)

		let rendered = try #require(
			TVCLogRenderer.renderTemplate(template, attributes: Self.fixedLine),
			"\(theme) failed to render the fixed line"
		)

		#expect(Self.normalized(rendered) == theme.expectedLine)
	}

	@Test("A theme's own template is the one that resolves", arguments: BundledTheme.all)
	func overriddenTemplateRendersToItsPinnedFragment(theme: BundledTheme) throws {
		var cache = ThemeTemplateCache(sources: Self.templateSources(for: theme))
		let compiled = cache.template(named: "encryptedMessageLock")

		let template = try #require(compiled, "\(theme) resolves no encrypted-message lock")

		let rendered = try #require(
			TVCLogRenderer.renderTemplate(template, attributes: Self.fixedLine),
			"\(theme) failed to render its encrypted-message lock"
		)

		#expect(Self.normalized(rendered) == theme.expectedLock)
	}

	// MARK: - The line

	/** One private message from `alice`, encrypted, at a fixed timestamp.

	 Every attribute the message template reads is set, including the ones it
	 reads only to decide whether to write an element at all, so the fragment
	 covers those branches rather than the empty case of most of them. */
	static var fixedLine: [String: Any] {
		[
			"applicationResourcePath": "/Resources",
			"formattedMessage": "hello &amp; welcome",
			"formattedNickname": "<alice>",
			"formattedTimestamp": "[12:34:56]",
			"highlightAttribute": "false",
			"inlineMediaEnabled": true,
			"isEncrypted": true,
			"isRemoteMessage": false,
			"lineClassAttribute": "text",
			"lineNumber": "0000-0000",
			"lineType": "privmsg",
			"localizedTimestamp": "12:34:56 on 1 January 2020",
			"messageIdentifier": "abc123",
			"nickname": "alice",
			"nicknameColorHashingEnabled": false,
			"nicknameType": "normal",
			"timestamp": "1577881496",
		]
	}

	// MARK: - Helpers

	/** The template repositories a theme renders through: its variety's, then
	 the theme's own, then the application's bundled defaults -- the order
	 `Theme.combineFiles()` builds. */
	static func templateSources(for theme: BundledTheme) -> ThemeTemplateSources {
		let themeURL = PathInfo.bundledThemesURL.appending(path: theme.name, directoryHint: .isDirectory)

		let varietyURL = themeURL
			.appending(path: ThemeResourcePath.varieties.rawValue, directoryHint: .isDirectory)
			.appending(path: theme.variety, directoryHint: .isDirectory)
			.appending(path: ThemeResourcePath.templates.rawValue, directoryHint: .isDirectory)

		let fallbackURL = PathInfo.applicationResourcesURL
			.appending(path: ThemeResourcePath.defaultTemplates.rawValue, directoryHint: .isDirectory)
			.appending(
				path: "Version \(TPCThemeSettingsNewestTemplateEngineVersion)",
				directoryHint: .isDirectory
			)

		return ThemeTemplateSources(
			repositoryURLs: [
				varietyURL,
				themeURL.appending(path: ThemeResourcePath.templates.rawValue, directoryHint: .isDirectory),
			],
			fallbackURL: fallbackURL,
			generation: 1
		)
	}

	/** Runs of whitespace collapsed to one space.

	 The renderer already strips newlines; what is left is the templates' own
	 indentation, which no browser and no stylesheet can see. Pinning it would
	 make a re-indented template look like a markup change. */
	static func normalized(_ html: String) -> String {
		html
			.split(whereSeparator: \.isWhitespace)
			.joined(separator: " ")
	}
}

private nonisolated extension BundledThemeRenderTests.BundledTheme {
	/** Both bundled themes render this, because neither overrides the message
	 template and a Mustache partial resolves inside the repository that owns
	 its parent: the `encryptionLock` span here is the application's empty
	 default, not the theme's own file, which the second test pins directly. */
	static let expectedSharedLine = """
	<div class="line text" id="line-0000-0000" data-command="" data-encrypted="true" \
	data-highlight="false" data-line-type="privmsg" data-msgid="abc123" data-member-type="normal" \
	data-timestamp="1577881496"> <p> <span class="time" title="12:34:56 on 1 January 2020" \
	>[12:34:56] </span> <span class="encryptionLock"></span> <span class="message"> \
	<span class="senderContainer"> <span class="sender" \
	onclick="Glasstual.nicknameMaybeWasDoubleClicked(this)" \
	oncontextmenu="Glasstual.openStandardNicknameContextualMenu()" data-member-type="normal" \
	data-nickname="alice" >&lt;alice&gt;</span> </span> <span class="innerMessage"> \
	hello &amp; welcome <span class="inlineMediaContainer"></span> </span> </span> </p></div>
	"""

	/// Both light varieties ship the same lock; the dark ones do not.
	static let expectedDarkIconLock = """
	<span class="encryptionLock"><img src="/Resources/encryptionLockIconDark.tiff" alt="[encrypted]" \
	title="This communication is encrypted." /></span>
	"""
}
