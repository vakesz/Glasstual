// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript settings snapshot", .serialized)
struct TranscriptSettingsStoreTests {
	/// A source the test changes by hand, standing in for the defaults store.
	private final class Source {
		var settings = TranscriptSettings()
	}

	private func window() -> MainWindow {
		MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		           styleMask: .borderless, backing: .buffered, defer: false)
	}

	@Test("The snapshot keeps what it read until it is refreshed")
	func keepsUntilRefreshed() {
		let source = Source()
		let store = TranscriptSettingsStore(read: { source.settings }, center: NotificationCenter())
		source.settings.showsDateChanges = false

		#expect(store.current.showsDateChanges)

		store.refresh()

		#expect(store.current.showsDateChanges == false)
	}

	@Test("A defaults notification refreshes it on a later turn")
	func catchAllNotification() async throws {
		let source = Source()
		let center = NotificationCenter()
		let store = TranscriptSettingsStore(read: { source.settings }, center: center)
		source.settings.textRules.detectsHighlightSpam = false
		center.post(name: UserDefaults.didChangeNotification, object: nil)

		try await Eventually.until("the snapshot to refresh") {
			store.current.textRules.detectsHighlightSpam == false
		}
	}

	@Test("The next line is rendered against the refreshed settings, in every transcript")
	func nextLineSeesTheChange() {
		let source = Source()
		let store = TranscriptSettingsStore(read: { source.settings }, center: NotificationCenter())
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let first = TranscriptController(session: session, in: window, inlineImageLoader: .shared, settings: store)
		let second = TranscriptController(session: session, in: window, inlineImageLoader: .shared, settings: store)
		defer {
			first.tearDown(.permanentRemoval)
			second.tearDown(.permanentRemoval)
		}
		#expect(first.ensureBackingView().dayMarkers != nil)

		source.settings.showsDateChanges = false
		source.settings.textRules.highlightMatchingMethod = .regularExpression
		source.settings.textRules.linkSchemes = LinkSchemeRules(permitsAnyScheme: true, permittedSchemes: ["x-test"])
		store.refresh()

		for controller in [first, second] {
			let context = controller.makeRenderContext()
			#expect(controller.ensureBackingView().dayMarkers == nil)
			#expect(context.textPolicy.highlightMatchingMethod == .regularExpression)
			#expect(context.textPolicy.linkSchemes.permittedSchemes == ["x-test"])
		}
	}

	@Test("The inline-media setting picks which half of the conversation's override applies")
	func inlineMediaFollowsTheSnapshot() throws {
		let source = Source()
		let store = TranscriptSettingsStore(read: { source.settings }, center: NotificationCenter())
		let session = TestServerSession()
		let conversation = try #require(session.findConversationOrCreate("#media"))
		let window = window()
		let controller = TranscriptController(conversation: conversation, in: window, settings: store)
		defer { controller.tearDown(.permanentRemoval) }
		func override(disabled: Bool, enabled: Bool) {
			var config = conversation.config
			config.inlineMediaDisabled = disabled
			config.inlineMediaEnabled = enabled
			conversation.updateConfig(config)
		}
		override(disabled: true, enabled: false)

		source.settings.showsInlineMedia = true
		store.refresh()
		#expect(controller.inlineMediaEnabledForView == false)

		source.settings.showsInlineMedia = false
		store.refresh()
		#expect(controller.inlineMediaEnabledForView == false)

		override(disabled: true, enabled: true)
		#expect(controller.inlineMediaEnabledForView)
	}

	@Test("An in-app write reaches the shared store before the reload returns")
	func reloadRefreshesTheSharedStore() {
		let key = SettingsKeys.Messages.detectHighlightSpam
		let original = key.value
		defer {
			key.value = original
			SettingsReload.perform(.transcriptSettings)
		}

		key.value = !original
		SettingsReload.perform(SettingsReload.action(forKeys: [key.name]).subtracting(.wholeSessionOnly))

		#expect(AppServices.transcriptSettings.current.textRules.detectsHighlightSpam == !original)
	}
}
