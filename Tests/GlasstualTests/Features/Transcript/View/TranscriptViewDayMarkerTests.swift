// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** A date marker sits before the first line of each day the transcript draws,
 in the reader's time zone, wherever the lines around it came from: printed
 live, put in above, or recovered into a gap. Lines arrive carrying whatever
 marker they were printed with, which says nothing about their new neighbours. */
@MainActor
@Suite("Transcript view day markers")
struct TranscriptViewDayMarkerTests {
	@Test("Recovered lines that cross midnight take the marker from the line that had it")
	func insertionCrossingMidnight() {
		let view = makeTranscriptView()
		view.appendLines([line("a", day: 10, hour: 22, dated: true), line("d", day: 11, hour: 9, dated: true)])

		view.insertRecoveredLines([line("b", day: 10, hour: 23), line("c", day: 11, hour: 0, minute: 30)])

		#expect(view.displayedLines.map(\.lineNumber) == ["a", "b", "c", "d"])
		#expect(datedLines(in: view) == ["a", "c"])
		#expect(drawnMarkers(in: view) == [caption(day: 10), caption(day: 11)])
	}

	@Test("Recovered lines within one day leave it with its one marker")
	func insertionWithinADay() {
		let view = makeTranscriptView()
		view.appendLines([line("a", day: 10, hour: 10, dated: true), line("c", day: 10, hour: 12)])

		view.insertRecoveredLines([line("b", day: 10, hour: 11, dated: true)])

		#expect(view.displayedLines.map(\.lineNumber) == ["a", "b", "c"])
		#expect(datedLines(in: view) == ["a"])
		#expect(drawnMarkers(in: view) == [caption(day: 10)])
	}

	@Test("A recovered line that is now the first of its day makes the marker below it redundant")
	func insertionMakesAMarkerRedundant() {
		let view = makeTranscriptView()
		view.appendLines([line("a", day: 10, hour: 23, dated: true), line("c", day: 11, hour: 10, dated: true)])

		view.insertRecoveredLines([line("b", day: 11, hour: 1)])

		#expect(datedLines(in: view) == ["a", "b"])
		#expect(drawnMarkers(in: view) == [caption(day: 10), caption(day: 11)])
	}

	@Test("Recovered lines bring the marker of a day that had none")
	func insertionIntroducesADay() {
		let view = makeTranscriptView()
		view.appendLines([line("a", day: 10, hour: 23, dated: true), line("d", day: 12, hour: 10, dated: true)])

		view.insertRecoveredLines([line("b", day: 11, hour: 8), line("c", day: 11, hour: 9)])

		#expect(datedLines(in: view) == ["a", "b", "d"])
		#expect(drawnMarkers(in: view) == [caption(day: 10), caption(day: 11), caption(day: 12)])
	}

	@Test("Older lines that cross midnight are marked once per day, and the old first line gives its marker up")
	func prependCrossingMidnight() {
		let view = makeTranscriptView()
		view.appendLines([line("c", day: 11, hour: 0, minute: 10, dated: true), line("d", day: 11, hour: 9)])

		view.prependLines([line("a", day: 10, hour: 23, minute: 50), line("b", day: 11, hour: 0, minute: 5)])

		#expect(view.displayedLines.map(\.lineNumber) == ["a", "b", "c", "d"])
		#expect(datedLines(in: view) == ["a", "b"])
		#expect(drawnMarkers(in: view) == [caption(day: 10), caption(day: 11)])
	}

	@Test("Older lines of the first drawn day move its marker to the top")
	func prependWithinADay() {
		let view = makeTranscriptView()
		view.appendLines([line("c", day: 11, hour: 8, dated: true), line("d", day: 11, hour: 9)])

		view.prependLines([line("a", day: 11, hour: 6, dated: true), line("b", day: 11, hour: 7, dated: true)])

		#expect(datedLines(in: view) == ["a"])
		#expect(drawnMarkers(in: view) == [caption(day: 11)])
	}

	/** 14:30 and 15:30 UTC are one afternoon in London and either side of
	 midnight in Tokyo. */
	@Test("The day is the one the reader's time zone puts a line in", arguments: [
		("Asia/Tokyo", ["a", "c"]),
		("Europe/London", ["a"]),
	])
	func timeZoneDecidesTheDay(zone: String, expected: [String]) throws {
		let view = makeTranscriptView()
		view.dayCalendar = try calendar(in: zone)
		let utc = try calendar(in: "UTC")
		func row(_ name: String, hour: Int, minute: Int) throws -> TranscriptRow {
			let date = try #require(utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute)))
			return line(name, at: date)
		}
		try view.appendLines([row("a", hour: 14, minute: 0), row("d", hour: 16, minute: 0)])

		try view.insertRecoveredLines([row("b", hour: 14, minute: 30), row("c", hour: 15, minute: 30)])

		#expect(view.displayedLines.map(\.lineNumber) == ["a", "b", "c", "d"])
		#expect(datedLines(in: view) == expected)
		#expect(drawnMarkers(in: view).count == expected.count)
	}

	@Test("A reader who scrolled up keeps their line when a marker is added or removed above it",
	      arguments: [false, true])
	func markerAboveTheReaderDoesNotMoveThem(prepends: Bool) throws {
		let view = makeTranscriptView()
		let rows = (0 ..< 200).map { line("line \($0)", day: 11, hour: 1, second: $0 * 10, dated: $0 == 0) }
		view.appendLines([line("first", day: 10, hour: 23, dated: true)] + rows)
		view.layoutSubtreeIfNeeded()
		view.followsBottom = false
		_ = view.jump(to: "line 100")
		view.layoutSubtreeIfNeeded()
		let before = try #require(view.viewportAnchor())

		if prepends {
			view.prependLines([line("older", day: 10, hour: 22)])
			#expect(datedLines(in: view) == ["older", "line 0"])
		} else {
			view.insertRecoveredLines([line("gap", day: 11, hour: 0, minute: 30)])
			#expect(datedLines(in: view) == ["first", "gap"])
		}

		let after = try #require(view.viewportAnchor())
		#expect(after.endpoint.lineNumber == before.endpoint.lineNumber)
		#expect(abs(after.offset - before.offset) < 1)
	}

	/** Older history loads when the reader reaches the top, so the marker at
	 the top of the viewport is the one a prepend most often takes away. The
	 text below it stays where it was. */
	@Test("A reader looking at the first line's marker keeps that line when older lines take the marker")
	func readerOnTheFirstMarkerKeepsItsLine() throws {
		let view = makeTranscriptView()
		view.appendLines((0 ..< 200).map { line("line \($0)", day: 11, hour: 1, second: $0 * 10, dated: $0 == 0) })
		view.layoutSubtreeIfNeeded()
		view.followsBottom = false
		_ = view.jump(to: "line 0")
		scroll(view, to: view.textView.textContainerOrigin.y + 4)
		let anchor = try #require(view.viewportAnchor())
		#expect(anchor.endpoint.lineNumber == "line 0")
		#expect(anchor.endpoint.segment != "marker-date")
		let before = try #require(viewportOffset(of: "line 0 body", in: view))

		view.prependLines((0 ..< 40).map { line("older \($0)", day: 11, hour: 0, second: $0, dated: false) })

		#expect(datedLines(in: view) == ["older 0"])
		let after = try #require(viewportOffset(of: "line 0 body", in: view))
		#expect(abs(after - before) < 1)
	}

	/// How far below the top of the viewport `text` is drawn.
	private func viewportOffset(of text: String, in view: TranscriptView) -> CGFloat? {
		let index = (view.textView.string as NSString).range(of: text).location
		guard index != NSNotFound, let layoutManager = view.textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager,
		      let location = contentManager.location(contentManager.documentRange.location, offsetBy: index)
		else { return nil }
		layoutManager.textViewportLayoutController.layoutViewport()
		let range = NSTextRange(location: location)
		layoutManager.ensureLayout(for: range)
		var top: CGFloat?
		layoutManager.enumerateTextSegments(in: range, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
			top = frame.minY
			return false
		}
		return top.map { $0 + view.textView.textContainerOrigin.y - view.scrollView.contentView.bounds.minY }
	}

	private func scroll(_ view: TranscriptView, to top: CGFloat) {
		view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
		view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
		view.layoutSubtreeIfNeeded()
		view.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
	}

	@Test("A reader who changes time zone has the days marked again in the new one")
	func timeZoneChangeMarksTheDaysAgain() throws {
		let view = makeTranscriptView()
		let utc = try calendar(in: "UTC")
		let dates = try [14, 16].map { hour in
			try #require(utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour)))
		}
		view.appendLines([line("a", at: dates[0]), line("b", at: dates[1])])
		#expect(datedLines(in: view) == ["a", "b"])

		view.dayCalendar = try calendar(in: "Europe/London")
		view.reloadClock()

		#expect(datedLines(in: view) == ["a"])
		#expect(drawnMarkers(in: view).count == 1)
	}

	@Test("A reader who turned date changes off is shown no marker, whatever a line arrives with")
	func noMarkersWhenTurnedOff() {
		var settings = TranscriptSettings.current()
		settings.showsDateChanges = false
		let fixture = Fixture(settings: TranscriptSettingsStore(read: { settings }, center: NotificationCenter()))
		let view = fixture.view
		view.dayCalendar = tokyo
		view.appendLines([line("a", day: 10, hour: 22, dated: true), line("d", day: 11, hour: 9, dated: true)])

		view.insertRecoveredLines([line("b", day: 10, hour: 23), line("c", day: 11, hour: 0, minute: 30)])
		view.prependLines([line("z", day: 9, hour: 1, dated: true)])

		withExtendedLifetime(fixture) {
			#expect(view.displayedLines.map(\.lineNumber) == ["z", "a", "b", "c", "d"])
			#expect(datedLines(in: view).isEmpty)
			#expect(drawnMarkers(in: view).isEmpty)
		}
	}

	@Test("The unread marker, a reaction, a redaction and a fold survive a marker moving off their line")
	func surroundingStateSurvives() throws {
		let view = makeTranscriptView()
		let conversation = try #require(view.viewController?.associatedConversation)
		var config = conversation.config
		config.generalEventMessageDisplay = .collapse
		conversation.updateConfig(config, fireChangedNotification: false, updateStoredConversationList: false)
		view.appendLines([
			line("a", day: 10, hour: 23, dated: true),
			line("join", day: 11, hour: 10, dated: true, kind: .join),
			line("part", day: 11, hour: 10, minute: 1, kind: .part),
			line("d", day: 11, hour: 11),
		])
		view.updateReactions(["+1": ["bob"]], messageIdentifier: "id-d")
		view.redactMessage(withIdentifier: "id-a", placeholder: "deleted")
		view.setUnreadMarker(.line("join"))
		#expect(view.document.folding.presentations["join"] == .summary(kind: .generalEvents, count: 2, expanded: false))

		view.insertRecoveredLines([line("quit", day: 11, hour: 9, kind: .quit)])

		let rows = Dictionary(uniqueKeysWithValues: view.displayedLines.map { ($0.lineNumber, $0) })
		#expect(datedLines(in: view) == ["a", "quit"])
		#expect(rows["join"]?.markers.map(\.selectionSegment) == ["marker-unread"])
		#expect(rows["d"]?.reactions == ["+1": ["bob"]])
		#expect(rows["a"]?.lineType == .redacted)
		/* The unread boundary still splits the events: one before it, two after. */
		#expect(view.document.folding.presentations["quit"] == .summary(kind: .generalEvents, count: 1, expanded: false))
		#expect(view.document.folding.presentations["join"] == .summary(kind: .generalEvents, count: 2, expanded: false))
		#expect(view.document.folding.presentations["part"] == .hidden)
		#expect(view.textView.string.contains("part body") == false)
		#expect(drawnMarkers(in: view) == [caption(day: 10), caption(day: 11)])
	}

	@Test("Events on either side of a marker that moved away fold into one group")
	func foldJoinsAcrossARemovedMarker() throws {
		let view = makeTranscriptView()
		let conversation = try #require(view.viewController?.associatedConversation)
		var config = conversation.config
		config.generalEventMessageDisplay = .collapse
		conversation.updateConfig(config, fireChangedNotification: false, updateStoredConversationList: false)
		view.appendLines([
			line("join", day: 11, hour: 10, dated: true, kind: .join),
			line("part", day: 11, hour: 10, minute: 1, kind: .part),
		])

		view.prependLines([line("quit", day: 11, hour: 9, kind: .quit)])

		#expect(datedLines(in: view) == ["quit"])
		#expect(view.document.folding.presentations["quit"] == .summary(kind: .generalEvents, count: 3, expanded: false))
		#expect(view.document.folding.presentations["join"] == .hidden)
		#expect(view.textView.string.contains("join body") == false)
		#expect(drawnMarkers(in: view) == [caption(day: 11)])
	}

	@Test("Trimming the oldest lines leaves the first line left with its day's marker")
	func trimKeepsTheFirstDayMarked() {
		let view = makeTranscriptView()
		view.setBufferLimit(8)
		view.appendLines((0 ..< 8).map { line("line \($0)", day: 10, hour: 1, second: $0, dated: $0 == 0) })

		view.appendLines((8 ..< 12).map { line("line \($0)", day: 10, hour: 1, second: $0) })

		#expect(view.displayedLines.count == 8)
		#expect(datedLines(in: view) == [view.displayedLines[0].lineNumber])
		#expect(drawnMarkers(in: view) == [caption(day: 10)])
	}

	// MARK: - Fixture

	private func calendar(in zone: String) throws -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = try #require(TimeZone(identifier: zone))
		return calendar
	}

	/// Tokyo keeps no daylight time, and is far enough from UTC that a test
	/// that read the wrong zone would not pass by accident.
	private var tokyo: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
		return calendar
	}

	private func caption(day: Int) -> String {
		let date = tokyo.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12)) ?? .distantPast
		return TranscriptDayMarkers(calendar: tokyo).caption(for: date)
	}

	/// The lines that carry a date marker, and each of them exactly one.
	private func datedLines(in view: TranscriptView) -> [String] {
		view.displayedLines.flatMap { row in
			row.markers.filter { $0.selectionSegment == "marker-date" }.map { _ in row.lineNumber }
		}
	}

	/// The date markers the text storage draws, top to bottom.
	private func drawnMarkers(in view: TranscriptView) -> [String] {
		guard let storage = view.textView.textStorage else { return [] }
		var captions: [String] = []
		storage.enumerateAttribute(
			.transcriptSelectionSegment, in: NSRange(location: 0, length: storage.length)
		) { value, range, _ in
			guard value as? String == "marker-date" else { return }
			captions.append(storage.attributedSubstring(from: range).string.trimmingCharacters(in: .newlines))
		}
		return captions
	}

	/// The view holds its controller weakly, and the controller its
	/// conversation and window, so the suite keeps all of them for the test.
	@MainActor
	private final class Fixture {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let conversation = Conversation(config: ConversationConfig(name: "#swift"))
		let controller: TranscriptController
		let view: TranscriptView

		init(settings: TranscriptSettingsStore = AppServices.transcriptSettings) {
			window.isReleasedWhenClosed = false
			controller = TranscriptController(
				conversation: conversation, in: window, settings: settings, commands: TranscriptCommandSink()
			)
			view = controller.ensureBackingView()
			view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
			window.contentView = view
			view.setBufferLimit(1000)
		}
	}

	private let fixture = Fixture()

	private func makeTranscriptView() -> TranscriptView {
		fixture.view.dayCalendar = tokyo
		return fixture.view
	}

	/** A line in March 2026, Tokyo time. `dated` is the marker it arrives
	 with, as the line that printed it decided against whatever came before
	 it then. */
	private func line(
		_ name: String, day: Int, hour: Int, minute: Int = 0, second: Int = 0,
		dated: Bool = false, kind: ChatLineKind = .privateMessage
	) -> TranscriptRow {
		let date = tokyo.date(from: DateComponents(
			year: 2026, month: 3, day: day, hour: hour, minute: minute, second: second
		)) ?? .distantPast
		var row = line(name, at: date, kind: kind)
		row.markers = dated ? [.date("printed with")] : []
		return row
	}

	private func line(_ name: String, at date: Date, kind: ChatLineKind = .privateMessage) -> TranscriptRow {
		TranscriptRow(
			lineNumber: name,
			receivedAt: date,
			nickname: "alice",
			memberType: .normal,
			lineType: kind,
			command: "PRIVMSG",
			messageIdentifier: "id-\(name)",
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: "\(name) body", runs: [TranscriptTextRun(text: "\(name) body")])
		)
	}
}
