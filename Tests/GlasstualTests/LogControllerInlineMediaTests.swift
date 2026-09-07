/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

nonisolated enum TranscriptMediaRetirement: CaseIterable, Sendable { // nonisolated: value
	case trim, clear, replacement
}

@MainActor
private final class TranscriptMediaFixture {
	let client: IRCClient
	let window: MainWindow
	let controller: LogController
	let view: LogView
	let budget = NativeInlineImageBudget()
	var line = LogLine()

	init() {
		client = IRCClient(config: ClientConfig())
		window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		controller = LogController(
			client: client, in: window,
			inlineImageLoader: NativeInlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		)
		controller.historyPageFetcher = { _ in .page([]) }
		view = controller.ensureBackingView()
		line.messageBody = "image"
		line.lineType = .privateMessage
	}

	func populate() async {
		await controller.drainRenderJobs()
		controller.print(line)
		await controller.drainRenderJobs()
	}

	func waitForWorker() async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while budget.activeCount > 0, clock.now < deadline {
			try await Task.sleep(for: .milliseconds(1))
		}
		try #require(budget.activeCount == 0)
	}
}

@MainActor
@Suite("Controller inline-media ownership", .serialized)
struct LogControllerInlineMediaTests {
	private func imageData() throws -> Data {
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		return try #require(bitmap.representation(using: .png, properties: [:]))
	}

	@Test("Completed previews are released on trim, clear and replacement using the same row ID",
	      arguments: TranscriptMediaRetirement.allCases)
	func retiredPreviewReleasesBudget(retirement: TranscriptMediaRetirement) async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let fixture = TranscriptMediaFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		await fixture.populate()
		let url = try InlineImageTestProtocol.register(.init(
			headers: ["Content-Type": "image/png"],
			chunk: imageData()
		))
		defer { InlineImageTestProtocol.remove(url) }
		try #require(fixture.controller.processInlineMediaAtAddress(
			url.absoluteString, withUniqueIdentifier: "link", atLineNumber: fixture.line.uniqueIdentifier
		) != nil)
		try await fixture.waitForWorker()
		#expect(fixture.budget.entryCount == 1)
		#expect(fixture.budget.reservedByteCount > 0)
		fixture.view.applyTheme()
		#expect(fixture.budget.entryCount == 1)
		switch retirement {
		case .trim:
			fixture.view.setBufferLimit(1)
			fixture.controller.print(LogLine())
			await fixture.controller.drainRenderJobs()
		case .clear: fixture.view.clearLines()
		case .replacement: fixture.view.replaceLines(fixture.view.displayedLines)
		}
		#expect(fixture.budget.entryCount == 0)
		#expect(fixture.budget.reservedByteCount == 0)
		let scroll = try #require(fixture.view.view.subviews.compactMap { $0 as? NSScrollView }.first)
		let text = try #require(scroll.documentView as? NSTextView)
		var attachments = 0
		text.textStorage?.enumerateAttribute(
			.attachment,
			in: NSRange(location: 0, length: (text.string as NSString).length)
		) { value, _, _ in
			if value != nil {
				attachments += 1
			}
		}
		#expect(attachments == 0)
	}

	@Test("A refused completion releases its token without removing the retained attachment")
	func refusedCompletionReleasesToken() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let fixture = TranscriptMediaFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		await fixture.populate()
		let data = try imageData()
		let url = InlineImageTestProtocol.register(.init(headers: ["Content-Type": "image/png"], chunk: data))
		defer { InlineImageTestProtocol.remove(url) }
		#expect(fixture.view.addInlineImage(TranscriptInlineImage(
			lineNumber: fixture.line.uniqueIdentifier, linkIdentifier: "link", sourceURL: url, imageData: data
		)))
		try #require(fixture.controller.processInlineMediaAtAddress(
			url.absoluteString, withUniqueIdentifier: "link", atLineNumber: fixture.line.uniqueIdentifier
		) != nil)
		try await fixture.waitForWorker()
		#expect(fixture.budget.entryCount == 0)
		#expect(fixture.budget.reservedByteCount == 0)
		#expect(!fixture.view.addInlineImage(TranscriptInlineImage(
			lineNumber: fixture.line.uniqueIdentifier, linkIdentifier: "link", sourceURL: url, imageData: data
		)))
	}

	@Test("Clear retires active requests and an old token cannot cancel the replacement")
	func generationCancellationKeepsReplacementToken() async throws {
		let lazy = Preferences.Logging.loadHistoryLazily.value
		Preferences.Logging.loadHistoryLazily.value = false
		defer { Preferences.Logging.loadHistoryLazily.value = lazy }
		let fixture = TranscriptMediaFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		await fixture.populate()
		let url = InlineImageTestProtocol.register(.init(hold: true))
		defer { InlineImageTestProtocol.remove(url) }
		let old = try #require(fixture.controller.processInlineMediaAtAddress(
			url.absoluteString, withUniqueIdentifier: "link", atLineNumber: fixture.line.uniqueIdentifier
		))
		#expect(fixture.budget.activeCount == 1)
		fixture.controller.clear()
		await fixture.controller.drainRenderJobs()
		try await fixture.waitForWorker()
		#expect(fixture.budget.entryCount == 0)
		await fixture.populate()
		let replacement = try #require(fixture.controller.processInlineMediaAtAddress(
			url.absoluteString, withUniqueIdentifier: "link", atLineNumber: fixture.line.uniqueIdentifier
		))
		#expect(replacement != old)
		fixture.controller.inlineImageLoader.cancelLoad(old)
		#expect(fixture.budget.activeCount == 1)
		fixture.controller.inlineImageLoader.cancelLoad(replacement)
		try await fixture.waitForWorker()
		#expect(fixture.budget.entryCount == 0)
	}
}
