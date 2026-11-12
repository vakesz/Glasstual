// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** What a highlighted run is drawn in, measured where it is drawn.

 The palette tests hold the highlight's two roles against each other. These
 read the colours the view actually gives a run, because a run that names a
 person or a channel used to take that action's colour and keep the
 highlight's ground: a pale nickname on yellow. */
@MainActor
@Suite("Transcript view highlight contrast")
struct TranscriptViewHighlightContrastTests {
	@Test(
		"A highlighted run clears AA contrast in every shipped theme, whatever it names",
		arguments: [false, true], [false, true]
	)
	func highlightedRunsStayLegible(isDark: Bool, increasesContrast: Bool) throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let appearance = try #require(NSAppearance(named: isDark ? .darkAqua : .aqua))
		source.appearance = ThemeAppearance(
			isDark: isDark,
			increasesContrast: increasesContrast,
			systemColors: .resolve(in: appearance, increasesContrast: increasesContrast)
		)
		let store = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}
		let runs = [
			TranscriptTextRun(text: "keyword", traits: .highlighted),
			TranscriptTextRun(text: "casey", traits: .highlighted, action: .nickname("casey")),
			TranscriptTextRun(text: "#swift", traits: .highlighted, action: .channel("#swift")),
		]

		for theme in TranscriptThemePreset.allShippedThemes {
			#expect(store.apply(theme))
			let view = makeTranscriptView(themeStore: store)
			view.appendLines([line(runs)])
			let storage = try #require(view.textView.textStorage)
			let ground = store.resolved(theme.palette.highlightBackground)
			for run in runs {
				let location = (storage.string as NSString).range(of: run.text).location
				try #require(location != NSNotFound)
				let text = try #require(storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)
				let background = try #require(storage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor)
				#expect(background == ground)
				let ratio = text.contrastRatio(against: background)
				#expect(
					ratio >= 4.5,
					"\(theme.name) \(theme.layout) \(run.text) \(isDark ? "dark" : "light") contrast \(increasesContrast): \(ratio)"
				)
			}
		}
	}

	@Test("An action still colours a run that is not highlighted")
	func plainActionRunsKeepTheirColour() throws {
		let view = makeTranscriptView(themeStore: AppServices.theme)
		view.appendLines([line([TranscriptTextRun(text: "#swift", action: .channel("#swift"))])])
		let storage = try #require(view.textView.textStorage)
		let location = (storage.string as NSString).range(of: "#swift").location
		let text = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
		#expect(text == AppServices.theme.resolved(AppServices.theme.theme.palette.link))
	}

	private func makeTranscriptView(themeStore: ThemeStore) -> TranscriptView {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let view = TranscriptView(viewController: controller, themeStore: themeStore)
		view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		view.setBufferLimit(100)
		return view
	}

	private func line(_ runs: [TranscriptTextRun]) -> TranscriptRow {
		let text = runs.map(\.text).joined(separator: " ")
		var spaced: [TranscriptTextRun] = []
		for run in runs {
			if spaced.isEmpty == false {
				spaced.append(TranscriptTextRun(text: " "))
			}
			spaced.append(run)
		}
		return TranscriptRow(
			lineNumber: UUID().uuidString,
			receivedAt: Date(),
			nickname: "marlow",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: nil,
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: text, runs: spaced, isHighlight: true)
		)
	}
}
