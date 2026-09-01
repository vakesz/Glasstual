/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import GlasstualPluginKit
import Testing

@Suite("Plugin runtime")
struct PluginRuntimeMigrationTests {
	@MainActor
	@Test(
		"Simple bundled plugin preferences are SwiftUI hosted",
		arguments: [
			("Caffeine", "TPI_Caffeine"),
			("Chat Filters", "TPI_ChatFilterExtension"),
			("Smiley Converter", "TPISmileyConverter"),
			("System Info", "TPISystemProfiler"),
		]
	)
	func simplePluginPreferencesAreSwiftUIHosted(
		_ fixture: (bundleName: String, legacyNibName: String)
	) throws {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("\(fixture.bundleName).bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		let suiteName = "PluginRuntimeMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }

		let preferenceView = try #require(plugin.pluginPreferencesPaneView)
		#expect(String(describing: type(of: preferenceView)).contains("NSHostingView"))
		#expect(bundle.path(forResource: fixture.legacyNibName, ofType: "nib") == nil)
	}

	@MainActor
	@Test("Chat Filters reads legacy property-list rules through its typed model")
	func chatFiltersReadsLegacyPropertyListRules() throws {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("Chat Filters.bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		let suiteName = "PluginRuntimeMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		defaults.set(
			[[
				"filterEventsNumerics": ["1"],
				"filterIgnoreContent": true,
				"filterMatch": "secret",
				"filterTitle": "Compatibility fixture",
			]],
			forKey: "Glasstual Chat Filter Extension -> Filters"
		)

		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }
		let filter = try #require(plugin.primaryClass as? any PluginTextEventHandling)
		let commandFilter = try #require(plugin.primaryClass as? any PluginIncomingCommandHandling)
		let client = makePluginClient()
		let author = PluginSender(
			nickname: "irc.example.test",
			username: nil,
			address: nil,
			hostmask: "irc.example.test",
			isServer: true
		)

		#expect(
			filter.receivedText(
				PluginTextEvent(
					text: "a secret message",
					author: author,
					destination: nil,
					kind: .privateMessage,
					client: client,
					receivedAt: Date(),
					wasEncrypted: false
				)
			) == false
		)
		#expect(
			filter.receivedText(
				PluginTextEvent(
					text: "an ordinary message",
					author: author,
					destination: nil,
					kind: .privateMessage,
					client: client,
					receivedAt: Date(),
					wasEncrypted: false
				)
			)
		)
		#expect(
			commandFilter.receivedCommand(
				PluginIncomingCommandEvent(
					command: "001",
					text: "another secret message",
					author: author,
					destination: nil,
					client: client,
					receivedAt: Date(),
					messageParameters: []
				)
			) == false
		)
	}

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

@MainActor
private func makePluginClient() -> PluginClient {
	PluginClient(
		identifier: "client",
		userNickname: "tester",
		networkName: "Test Network",
		serverAddress: "irc.example.test",
		isConnected: true,
		isLoggedIn: true,
		isIRCop: false,
		localUser: nil,
		channels: [],
		isConnectedToZNC: false,
		zncCertificateChainData: nil,
		maximumNicknameLength: 30,
		nicknameMatchesZNCUser: { $0 == $1 },
		isChannelName: { $0.hasPrefix("#") },
		findChannel: { _ in nil },
		privateMessage: { _ in nil },
		utilityChannel: { _ in nil },
		isCapabilityEnabled: { _ in false },
		printDebug: { _, _ in },
		sendPrivateMessage: { _, _ in },
		sendCommand: { _ in },
		sendLine: { _ in },
		joinChannel: { _ in },
		printMessage: { _, _, _, _, _, _, _, completion in completion(PluginPrintResult(isHighlight: false)) },
		markUnread: { _, _ in },
		markHighlight: { _ in },
		refreshSidebar: {}
	)
}
