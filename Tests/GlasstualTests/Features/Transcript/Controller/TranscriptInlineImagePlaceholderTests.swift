// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// A channel on a session behind the reader's own SOCKS5 proxy, whose
/// transcript fetches through a stubbed protocol and counts local lookups.
@MainActor
private final class ProxiedChannelFixture {
	let session: ServerSession
	let channel: Conversation
	let window: MainWindow
	let controller: TranscriptController
	let view: TranscriptView
	let budget = InlineImageBudget()
	let lookups = LookupCounter()

	init(inlineMedia: Bool = true) {
		var config = ServerConfig()
		config.proxyType = .socks5
		config.proxyAddress = "proxy.example.org"
		config.proxyPort = 1080
		session = ServerSession(config: config)
		var channelConfig = ConversationConfig(name: "#images")
		// Both halves, so the outcome does not depend on the app-wide setting.
		channelConfig.inlineMediaEnabled = inlineMedia
		channelConfig.inlineMediaDisabled = !inlineMedia
		channel = Conversation(config: channelConfig)
		channel.associatedSession = session
		channel.activate()
		window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let lookups = lookups
		controller = TranscriptController(
			conversation: channel, in: window,
			inlineImageLoader: InlineImageLoader(
				budget: budget,
				protocolClasses: [InlineImageTestProtocol.self],
				hostResolver: InlineImageHostResolver { host in await lookups.lookup(host) }
			)
		)
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		view = controller.ensureBackingView()
	}

	/// Prints a message that links to `url`, and answers with its line number.
	func printLink(to url: URL) async -> String {
		await controller.drainRenderJobs()
		var line = ChatLine()
		line.lineType = .privateMessage
		line.messageBody = "look \(url.absoluteString)"
		controller.print(line)
		await controller.drainRenderJobs()
		return line.uniqueIdentifier
	}

	func placeholders(on lineNumber: String) -> [TranscriptInlineImagePlaceholder] {
		(view.document.inlineMedia[lineNumber] ?? []).compactMap(\.placeholder)
	}

	func images(on lineNumber: String) -> Int {
		(view.document.inlineMedia[lineNumber] ?? []).count(where: { $0.placeholder == nil })
	}

	/// Placeholder characters the text storage holds.
	func drawnPlaceholders() throws -> Int {
		let storage = try #require(view.textView.textStorage)
		var count = 0
		storage.enumerateAttribute(
			.transcriptInlineImagePlaceholder, in: NSRange(location: 0, length: storage.length)
		) { value, _, _ in
			if value != nil {
				count += 1
			}
		}
		return count
	}
}

@MainActor
@Suite("Inline image placeholders", .serialized)
struct TranscriptInlineImagePlaceholderTests {
	private func pngData() throws -> Data {
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		return try #require(bitmap.representation(using: .png, properties: [:]))
	}

	@Test("A proxied session draws a placeholder and fetches nothing, through a redraw too")
	func proxiedRenderDrawsPlaceholder() async throws {
		let fixture = ProxiedChannelFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		let url = try InlineImageTestProtocol.register(.init(headers: ["Content-Type": "image/png"], chunk: pngData()))
		defer { InlineImageTestProtocol.remove(url) }

		let lineNumber = await fixture.printLink(to: url)

		let placeholder = try #require(fixture.placeholders(on: lineNumber).first)
		#expect(placeholder.sourceURL == url)
		#expect(placeholder.state == .ready)
		#expect(try fixture.drawnPlaceholders() == 1)
		#expect(fixture.budget.entryCount == 0)

		fixture.view.applyTheme()
		await fixture.controller.drainRenderJobs()

		#expect(fixture.placeholders(on: lineNumber) == [placeholder])
		#expect(try fixture.drawnPlaceholders() == 1)
		#expect(fixture.budget.entryCount == 0)
		#expect(InlineImageTestProtocol.startCount(url) == 0)
		#expect(await fixture.lookups.callCount == 0)
	}

	@Test("Activating a placeholder fetches once, through the proxy, and draws the image in its place",
	      .timeLimit(.minutes(1)))
	func activationFetchesOnce() async throws {
		let fixture = ProxiedChannelFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		let url = try InlineImageTestProtocol.register(.init(headers: ["Content-Type": "image/png"], chunk: pngData()))
		defer { InlineImageTestProtocol.remove(url) }
		let lineNumber = await fixture.printLink(to: url)
		let placeholder = try #require(fixture.placeholders(on: lineNumber).first)

		#expect(fixture.view.activateInlineImagePlaceholder(placeholder.key))
		#expect(fixture.placeholders(on: lineNumber).first?.state == .loading)
		// A second activation while the first is under way starts nothing.
		#expect(fixture.view.activateInlineImagePlaceholder(placeholder.key) == false)

		try await Eventually.until(timeout: .seconds(10), "the image to replace the placeholder") {
			fixture.images(on: lineNumber) == 1
		}
		#expect(fixture.placeholders(on: lineNumber).isEmpty)
		#expect(try fixture.drawnPlaceholders() == 0)
		#expect(InlineImageTestProtocol.startCount(url) == 1)
		// The system route looks a name up here; the proxy route never does.
		#expect(await fixture.lookups.callCount == 0)
	}

	@Test("A literal private address is refused even when the reader asks for it", arguments: [
		"http://192.168.1.10/a.png", "http://127.0.0.1/a.png", "https://[::1]/a.png", "https://printer.local/a.png",
	])
	func privateAddressIsRefusedOnRequest(address: String) async throws {
		let fixture = ProxiedChannelFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		let url = try #require(URL(string: address))

		let lineNumber = await fixture.printLink(to: url)
		// Such an address never gets a placeholder of its own to click.
		#expect(fixture.placeholders(on: lineNumber).isEmpty)

		let placeholder = TranscriptInlineImagePlaceholder(lineNumber: lineNumber, linkIdentifier: "forced", sourceURL: url)
		#expect(fixture.view.addInlineImagePlaceholder(placeholder))
		#expect(fixture.view.activateInlineImagePlaceholder(placeholder.key))

		#expect(fixture.budget.entryCount == 0)
		#expect(fixture.view.document.inlineImagePlaceholder(placeholder.key)?.state == .failed)
		#expect(fixture.controller.loadInlineImageOnRequest(placeholder) == nil)
		#expect(await fixture.lookups.callCount == 0)
	}

	@Test("With inline media off there is no placeholder, and an old one fetches nothing")
	func inlineMediaOffShowsNoPlaceholder() async throws {
		let fixture = ProxiedChannelFixture(inlineMedia: false)
		defer { fixture.controller.tearDown(.permanentRemoval) }
		let url = try InlineImageTestProtocol.register(.init(headers: ["Content-Type": "image/png"], chunk: pngData()))
		defer { InlineImageTestProtocol.remove(url) }

		let lineNumber = await fixture.printLink(to: url)
		#expect(fixture.placeholders(on: lineNumber).isEmpty)

		let placeholder = TranscriptInlineImagePlaceholder(lineNumber: lineNumber, linkIdentifier: "stale", sourceURL: url)
		#expect(fixture.view.addInlineImagePlaceholder(placeholder))
		#expect(fixture.view.activateInlineImagePlaceholder(placeholder.key))

		#expect(fixture.view.document.inlineImagePlaceholder(placeholder.key) == nil)
		#expect(fixture.budget.entryCount == 0)
		#expect(InlineImageTestProtocol.startCount(url) == 0)
	}

	@Test("A proxy with no address fails the requested fetch closed")
	func unavailableRouteFailsOnRequest() async throws {
		let fixture = ProxiedChannelFixture()
		defer { fixture.controller.tearDown(.permanentRemoval) }
		let url = try InlineImageTestProtocol.register(.init(headers: ["Content-Type": "image/png"], chunk: pngData()))
		defer { InlineImageTestProtocol.remove(url) }
		let lineNumber = await fixture.printLink(to: url)
		let placeholder = try #require(fixture.placeholders(on: lineNumber).first)

		fixture.session.config.proxyAddress = nil
		#expect(fixture.view.activateInlineImagePlaceholder(placeholder.key))

		#expect(fixture.budget.entryCount == 0)
		#expect(fixture.placeholders(on: lineNumber).first?.state == .failed)
		#expect(InlineImageTestProtocol.startCount(url) == 0)
	}
}
