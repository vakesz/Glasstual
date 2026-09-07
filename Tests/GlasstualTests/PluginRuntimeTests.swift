/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@Suite("Plugin runtime")
struct PluginRuntimeTests {
	@MainActor
	@Test(
		"ZNC buffextras bounds parsed server nickname counts before conversion",
		arguments: [UInt(3), 8, UInt(Int.max), UInt(Int.max) + 1, UInt.max]
	)
	func zncNicknameLimitReachesInterceptor(_ limit: UInt) throws {
		let bundleURL = PathInfo.bundledExtensionsURL.appendingPathComponent("ZNC Additions.bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		let suiteName = "PluginRuntimeTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }
		let interceptor = try #require(plugin.primaryClass as? any PluginServerMessageIntercepting)
		let info = IRCISupportInfo()
		info.processConfigurationData("NICKLEN=\(limit)")
		let client = makePluginClient(maximumNicknameLength: info.maximumNicknameLength, isConnectedToZNC: true)
		let input = PluginServerMessage(
			sender: PluginSender(
				nickname: "buffextras",
				username: nil,
				address: nil,
				hostmask: "buffextras",
				isServer: false
			),
			command: "PRIVMSG", parameters: ["#test", "alice!u@host joined"], isPrintOnlyMessage: false
		)
		let result = try #require(interceptor.interceptServerInput(input, client: client))
		#expect(result.command == "JOIN")
		#expect(result.sender.nickname == (limit < 5 ? "alice!u@host" : "alice"))
		#expect(result.sender.isServer == (limit < 5))
	}

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
		let suiteName = "PluginRuntimeTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }

		let preferencePane = try #require(plugin.pluginPreferencesPane)
		_ = preferencePane.makeView()
		#expect(preferencePane.title.isEmpty == false)
		#expect(bundle.path(forResource: fixture.legacyNibName, ofType: "nib") == nil)
	}

	@Test("Bundled boolean preference declarations preserve shipped names and defaults")
	func bundledPreferenceDefaultsMatchShippedContract() {
		let keys = [
			Preferences.Extensions.caffeinePreventSleep,
			Preferences.Extensions.smileyServiceEnabled,
			Preferences.Extensions.smileyExtraEmoticons,
		] + Preferences.Extensions.systemProfilerFeatures
		#expect(Dictionary(uniqueKeysWithValues: keys.map { ($0.name, $0.defaultValue) }) == [
			"Private Extension Store -> Caffeine Extension -> Prevent Sleep": false,
			"Smiley Converter Extension -> Enable Service": false,
			"Smiley Converter Extension -> Enable Extra Emoticons": false,
			"System Profiler Extension -> Feature Disabled -> CPU Model": false,
			"System Profiler Extension -> Feature Disabled -> Disk Information": true,
			"System Profiler Extension -> Feature Disabled -> GPU Model": true,
			"System Profiler Extension -> Feature Disabled -> Memory Information": true,
			"System Profiler Extension -> Feature Disabled -> OS Version": false,
			"System Profiler Extension -> Feature Disabled -> Screen Resolution": true,
			"System Profiler Extension -> Feature Disabled -> System Uptime": true,
		])
		let registrations = Preferences.registrationDomain(for: .container)
		for key in keys {
			#expect(key.registeredDefault == nil)
			#expect(registrations[key.name] == nil)
			#expect(Preferences.storage(for: key.name) == .container)
		}
	}

	@MainActor
	@Test(
		"Compiled plugins agree with typed defaults without changing registration or persistence policy",
		arguments: ["Caffeine", "Smiley Converter", "System Info"], [false, true]
	)
	func compiledPluginDefaultsMatchApp(_ bundleName: String, _ hasStoredOverrides: Bool) throws {
		let keys: [PreferenceKey<Bool>] = switch bundleName {
		case "Caffeine": [Preferences.Extensions.caffeinePreventSleep]
		case "Smiley Converter": [
				Preferences.Extensions.smileyServiceEnabled,
				Preferences.Extensions.smileyExtraEmoticons,
			]
		default: Preferences.Extensions.systemProfilerFeatures
		}
		let suiteName = "PluginRuntimeTests.\(UUID().uuidString)"
		let standardName = "PluginRuntimeTests.standard.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		let standard = try #require(UserDefaults(suiteName: standardName))
		defer {
			defaults.removePersistentDomain(forName: suiteName)
			standard.removePersistentDomain(forName: standardName)
		}
		let stores = PreferencesTransferStores(
			container: defaults, containerDomain: suiteName, standard: standard, standardDomain: standardName
		)
		let initialSnapshot = stores.snapshot(clients: [])
		for key in keys {
			#expect(stores[key] == key.defaultValue)
			// Registration defaults are process-wide, even for a fresh suite.
			if let value = defaults.object(forKey: key.name) as? Bool {
				#expect(initialSnapshot.values[key.name] == .boolean(value))
			} else {
				#expect(initialSnapshot.unset.contains(key.name))
			}
			if hasStoredOverrides {
				stores.set(.boolean(!key.defaultValue), for: key)
			}
		}
		let persistedBefore = defaults.persistentDomain(forName: suiteName) ?? [:]
		let bundle = try #require(Bundle(url: PathInfo.bundledExtensionsURL
				.appendingPathComponent("\(bundleName).bundle", isDirectory: true)))
		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }
		let pane = try #require(plugin.pluginPreferencesPane)
		_ = pane.makeView()

		let registrations = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
		let snapshot = stores.snapshot(clients: [])
		for key in keys {
			let expected = hasStoredOverrides ? !key.defaultValue : key.defaultValue
			#expect(defaults.bool(forKey: key.name) == expected)
			#expect(stores[key] == expected)
			let registered = bundleName == "System Info" && key.defaultValue
			#expect((registrations[key.name] as? Bool) == (registered ? true : nil))
			if hasStoredOverrides || registered {
				#expect(snapshot.values[key.name] == .boolean(expected))
				#expect(!snapshot.unset.contains(key.name))
			} else {
				#expect(snapshot.values[key.name] == nil)
				#expect(snapshot.unset.contains(key.name))
			}
		}
		#expect(NSDictionary(dictionary: defaults.persistentDomain(forName: suiteName) ?? [:])
			.isEqual(to: persistedBefore))
		#expect((standard.persistentDomain(forName: standardName) ?? [:]).isEmpty)
	}

	@MainActor
	@Test("Chat Filters reads legacy property-list rules through its typed model")
	func chatFiltersReadsLegacyPropertyListRules() async throws {
		let bundleURL = PathInfo.bundledExtensionsURL
			.appendingPathComponent("Chat Filters.bundle", isDirectory: true)
		let bundle = try #require(Bundle(url: bundleURL))
		let suiteName = "PluginRuntimeTests.\(UUID().uuidString)"
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

		// An import can write through a different handle and emit several
		// notifications in one turn. Every callback must read the final value.
		let importedDefaults = try #require(UserDefaults(suiteName: suiteName))
		importedDefaults.set([], forKey: "Glasstual Chat Filter Extension -> Filters")
		for _ in 0 ..< 3 {
			NotificationCenter.default.post(name: .textualUserDefaultsDidChange, object: importedDefaults)
		}
		try await waitForPluginUpdate {
			commandFilter.receivedCommand(PluginIncomingCommandEvent(
				command: "001", text: "another secret message", author: author,
				destination: nil, client: client, receivedAt: Date(), messageParameters: []
			))
		}
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
		let suiteName = "PluginRuntimeTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }

		defaults.set(true, forKey: "Smiley Converter Extension -> Enable Service")
		defaults.set(false, forKey: "Smiley Converter Extension -> Enable Extra Emoticons")

		let plugin = try #require(PluginItem.load(bundle, host: makePluginHost(defaults: defaults)))
		defer { plugin.unloadBundle() }

		let renderer = try #require(plugin.primaryClass as? any PluginMessageRendering)

		let renderTask = Task.detached { () -> [String] in
			(0 ..< 500).compactMap { _ in
				renderer.willRenderMessage(
					PluginRenderEvent(message: ":)", kind: .privateMessage)
				)
			}
		}

		let importedDefaults = try #require(UserDefaults(suiteName: suiteName))
		for iteration in 0 ..< 10 {
			let extraEnabled = iteration.isMultiple(of: 2)
			importedDefaults.set(
				extraEnabled,
				forKey: "Smiley Converter Extension -> Enable Extra Emoticons"
			)
			NotificationCenter.default.post(name: .textualUserDefaultsDidChange, object: importedDefaults)
			try await waitForPluginUpdate {
				renderer.willRenderMessage(PluginRenderEvent(message: ":+1:", kind: .privateMessage)) ==
					(extraEnabled ? "\u{1F44D}" : ":+1:")
			}
		}

		let renderedMessages = await renderTask.value
		#expect(renderedMessages.count == 500)
		#expect(renderedMessages.allSatisfy { $0 == "😊" })
		importedDefaults.removeObject(forKey: "Smiley Converter Extension -> Enable Service")
		NotificationCenter.default.post(name: .textualUserDefaultsDidChange, object: importedDefaults)
		try await waitForPluginUpdate {
			renderer.willRenderMessage(PluginRenderEvent(message: ":)", kind: .privateMessage)) == ":)"
		}
	}

	@MainActor
	@Test("Caffeine reevaluates connected clients when defaults change outside its pane")
	func caffeineObservesImportedDefaults() async throws {
		let bundle = try #require(Bundle(url: PathInfo.bundledExtensionsURL.appendingPathComponent("Caffeine.bundle")))
		let suiteName = "PluginRuntimeTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))
		let importedDefaults = try #require(UserDefaults(suiteName: suiteName))
		defer { defaults.removePersistentDomain(forName: suiteName) }
		var clientReads = 0
		let host = makePluginHost(defaults: defaults, clients: {
			clientReads += 1
			return []
		})
		let plugin = try #require(PluginItem.load(bundle, host: host))
		defer { plugin.unloadBundle() }
		let initialReads = clientReads
		importedDefaults.set(true, forKey: "Private Extension Store -> Caffeine Extension -> Prevent Sleep")
		NotificationCenter.default.post(name: .textualUserDefaultsDidChange, object: importedDefaults)
		try await waitForPluginUpdate { clientReads > initialReads }
	}

	@MainActor
	private func waitForPluginUpdate(_ predicate: () -> Bool) async throws {
		let deadline = ContinuousClock.now + .seconds(5)
		while !predicate(), ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(predicate(), "Plugin did not apply the effective defaults within five seconds")
	}
}

@MainActor
private func makePluginHost(defaults: UserDefaults,
                            clients: @escaping () -> [PluginClient] = { [] }) -> PluginHostContext
{
	PluginHostContext(
		defaults: defaults,
		clients: clients,
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
private func makePluginClient(maximumNicknameLength: UInt = 30, isConnectedToZNC: Bool = false) -> PluginClient {
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
		isConnectedToZNC: isConnectedToZNC,
		zncCertificateChainData: nil,
		maximumNicknameLength: maximumNicknameLength,
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
