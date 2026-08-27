/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
@_spi(Host) import GlasstualPluginKit
import XCTest

final class PluginRuntimeMigrationTests: XCTestCase {
	func testPluginItemNoLongerExportsLegacySourceLoadingSelector() {
		XCTAssertFalse(PluginItem.instancesRespond(to: NSSelectorFromString("loadBundle:")))
		XCTAssertTrue(PluginItem.instancesRespond(to: NSSelectorFromString("unloadBundle")))
	}

	func testSupportedFeaturesPreserveInternalBitAssignments() {
		XCTAssertEqual(PluginSupportedFeature.didReceiveCommandEvent.rawValue, 1 << 1)
		XCTAssertEqual(PluginSupportedFeature.didReceivePlainTextMessageEvent.rawValue, 1 << 2)
		XCTAssertEqual(PluginSupportedFeature.newMessagePostedEvent.rawValue, 1 << 4)
		XCTAssertEqual(PluginSupportedFeature.outputSuppressionRules.rawValue, 1 << 5)
		XCTAssertEqual(PluginSupportedFeature.preferencePane.rawValue, 1 << 6)
		XCTAssertEqual(PluginSupportedFeature.serverInputDataInterception.rawValue, 1 << 7)
		XCTAssertEqual(PluginSupportedFeature.subscribedServerInputCommands.rawValue, 1 << 8)
		XCTAssertEqual(PluginSupportedFeature.subscribedUserInputCommands.rawValue, 1 << 9)
		XCTAssertEqual(PluginSupportedFeature.userInputDataInterception.rawValue, 1 << 10)
		XCTAssertEqual(PluginSupportedFeature.webViewJavaScriptPayloads.rawValue, 1 << 11)
		XCTAssertEqual(PluginSupportedFeature.willRenderMessageEvent.rawValue, 1 << 12)
	}

	func testOutputSuppressionRulesUsePluginKitModel() {
		let rule = PluginOutputSuppressionRule()
		rule.match = "NOTICE"
		rule.restrictConsole = true

		XCTAssertEqual(rule.match, "NOTICE")
		XCTAssertTrue(rule.restrictConsole)
	}

	@MainActor
	func testSmileyConverterRendersFromCompleteSnapshotsDuringPreferenceReloads() async throws {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("Smiley Converter.bundle", isDirectory: true)
		let bundle = try XCTUnwrap(Bundle(url: bundleURL))
		let suiteName = "PluginRuntimeMigrationTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		defaults.set(true, forKey: "Smiley Converter Extension -> Enable Service")
		defaults.set(false, forKey: "Smiley Converter Extension -> Enable Extra Emoticons")

		let plugin = PluginItem()
		XCTAssertTrue(plugin.loadBundle(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }

		let primaryClass = try XCTUnwrap(plugin.primaryClass as? NSObject)
		let preferenceChanged = NSSelectorFromString("preferenceChanged:")
		XCTAssertTrue(primaryClass.responds(to: preferenceChanged))
		XCTAssertNotNil(plugin.primaryClass as? any PluginMessageRendering)

		let renderTask = Task.detached { () -> [String] in
			guard let renderer = plugin.primaryClass as? any PluginMessageRendering else { return [] }
			return (0 ..< 500).compactMap { _ in
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
		XCTAssertEqual(renderedMessages.count, 500)
		XCTAssertTrue(renderedMessages.allSatisfy { $0 == "😊" })
	}
}

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
		observeConnectionState: { handler in
			handler(false)
			return PluginObservation(cancellation: {})
		},
		removesFormatting: { false }
	)
}
