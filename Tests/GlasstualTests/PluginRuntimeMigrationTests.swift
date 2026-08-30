/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@Suite("Plugin runtime")
struct PluginRuntimeMigrationTests {
	@Test("An output suppression rule holds what it was given")
	func outputSuppressionRulesUsePluginKitModel() {
		var rule = PluginOutputSuppressionRule()
		rule.match = "NOTICE"
		rule.restrictConsole = true

		#expect(rule.match == "NOTICE")
		#expect(rule.restrictConsole)
	}

	@MainActor
	@Test("A preference reload never hands the renderer a half-built snapshot")
	func smileyConverterRendersFromCompleteSnapshotsDuringPreferenceReloads() async throws {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("Smiley Converter.bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		let suiteName = "PluginRuntimeMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		defaults.set(true, forKey: "Smiley Converter Extension -> Enable Service")
		defaults.set(false, forKey: "Smiley Converter Extension -> Enable Extra Emoticons")

		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }

		let primaryClass = try #require(plugin.primaryClass as? NSObject)
		let preferenceChanged = NSSelectorFromString("preferenceChanged:")
		#expect(primaryClass.responds(to: preferenceChanged))
		let renderer = try #require(plugin.primaryClass as? any PluginMessageRendering)

		let renderTask = Task.detached { () -> [String] in
			(0 ..< 500).compactMap { _ in
				renderer.willRenderMessage(
					PluginRenderEvent(message: ":)", kind: .privateMessage)
				)
			}
		}

		for iteration in 0 ..< 50 {
			defaults.set(
				iteration.isMultiple(of: 2),
				forKey: "Smiley Converter Extension -> Enable Extra Emoticons"
			)
			primaryClass.perform(preferenceChanged, with: nil)
			await Task.yield()
		}

		let renderedMessages = await renderTask.value
		#expect(renderedMessages.count == 500)
		#expect(renderedMessages.allSatisfy { $0 == "😊" })
	}
}

@MainActor
private func makePluginHost(defaults: UserDefaults) -> PluginHostContext {
	PluginHostContext(
		defaults: defaults,
		clients: { [] },
		selectedChannel: { nil },
		metrics: {
			PluginApplicationMetrics(
				messagesSent: 0,
				messagesReceived: 0,
				bandwidthIn: 0,
				bandwidthOut: 0,
				lastMessageReceived: 0,
				visibleLineCount: 0,
				usesDarkSidebar: false
			)
		},
		applicationSnapshot: { nil },
		themeSnapshot: { nil },
		observeConnectionState: { handler in
			handler(false)
			return PluginObservation(cancellation: {})
		},
		removesFormatting: { false }
	)
}
