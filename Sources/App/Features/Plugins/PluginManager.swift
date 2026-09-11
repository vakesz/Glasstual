/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit
import os
import Security
import Synchronization

/// The result of scanning the extension folders, expressed as file URLs so the
/// scan can run off the main actor and hand its findings back.
private nonisolated struct PluginDiscovery: Sendable { // nonisolated: value
	var loadable: [URL] = []
	var obsolete: [URL] = []
	var rejected: [URL] = []
	var scriptCatalog = PluginScriptCatalog()
	var scriptGeneration: UInt64 = 0
}

/** The AppleScript commands on disk, and which scan found them.

 The generation is what tells a stale scan from a current one: discovery and a
 refresh both run off the main actor and can land in either order, so a scan
 whose generation is no longer the reserved one has been overtaken and its
 catalog is dropped. */
private nonisolated struct PluginScriptFacts: Sendable { // nonisolated: value
	var commandsByName: [String: PluginScript] = [:]
	var customScriptsURL: URL?
	var generation: UInt64 = 0

	init() {}

	init(catalog: PluginScriptCatalog, generation: UInt64) {
		commandsByName = catalog.commandsByName
		customScriptsURL = catalog.customScriptsURL
		self.generation = generation
	}
}

/** What an add-on command typed into the input field is dispatched to.

 The client asks this before falling back to sending the command to the server
 as a raw line. Both an AppleScript and a loaded plugin can declare the same
 name, which is nothing the client can choose between, so that is a case of its
 own rather than a silent preference for one of them. */
public nonisolated enum OutgoingCommandHandler: Equatable, Sendable { // nonisolated: value
	/// Nothing claims the command.
	case none
	/// A script at this path. Kept as a path for existing command consumers.
	case script(path: String)
	/// A loaded plugin that declares the command.
	case pluginExtension
	/// Both a script and a plugin claim it.
	case ambiguous
}

/// Everything about the loaded plugins that a caller outside the main actor
/// needs: a plugin's own object stays on the main actor, but which features
/// exist, which commands are subscribed, and the suppression rules are values.
private nonisolated struct PluginFacts: Sendable { // nonisolated: value
	var pluginsLoaded = false
	var supportedFeatures: PluginSupportedFeature = []
	var outputSuppressionRules: [PluginOutputSuppressionRule] = []
	var supportedUserInputCommands: [String] = []
	var supportedServerInputCommands: [String] = []
	var scripts = PluginScriptFacts()

	init() {}

	@MainActor
	init(loadedPlugins: [PluginItem]) {
		var userInputCommands = Set<String>()
		var serverInputCommands = Set<String>()

		for plugin in loadedPlugins {
			supportedFeatures.formUnion(plugin.supportedFeatures)
			outputSuppressionRules.append(contentsOf: plugin.outputSuppressionRules)
			userInputCommands.formUnion(plugin.supportedUserInputCommands)
			serverInputCommands.formUnion(plugin.supportedServerInputCommands)
		}

		pluginsLoaded = true
		supportedUserInputCommands = userInputCommands.sorted()
		supportedServerInputCommands = serverInputCommands.sorted()
	}
}

/** The message renderers, as the transcript's queue reaches them.

 The plugin objects stay in `loadedPluginItems`, which is main-actor. What is
 published here is one `@Sendable` call per renderer — the single function
 `PluginMessageRendering` allows off the main actor — together with the
 generation of the load it belongs to. Nothing outside the plugin's own module
 can get from a call back to the object it belongs to, and the renderers are
 replaced wholesale rather than edited. */
private nonisolated struct PluginRendererFacts: Sendable { // nonisolated: value
	/// Bumped by every publish and by `unloadPlugins()`, so which load the
	/// published calls belong to is observable — from a log line, from a test
	/// that has to tell one list from an identical-looking next one, and by a
	/// render that has to notice it has been overtaken part-way through.
	var generation: UInt64 = 0
	var renderers: [@Sendable (PluginRenderEvent) -> String?] = []
}

/// Discovers, validates and loads Glasstual's plugin bundles.
///
/// Only first-party bundles load: one shipped inside the application, or one
/// installed by the user that is signed by the same Team ID. There is no
/// approval prompt — a bundle either satisfies the requirement or is refused
/// and logged.
///
/// Nonisolated because the transcript renderer reads it off the main actor:
/// `PluginDispatcher.willRenderMessage` and `LogController.makePluginMessage`
/// both run on the renderer's own queue, so the manager cannot move onto the
/// main actor with the plugin objects it loads. What those callers read is the
/// `Mutex`-guarded `PluginFacts` value below, and — for the one callback that
/// reaches a plugin off the main actor — `renderingMessage(_:kind:)`, which
/// calls the published renderers under the lock that retires them. The plugin
/// objects themselves stay in `loadedPluginItems`, which is main-actor.
public final nonisolated class PluginManager: NSObject, Sendable { // nonisolated: guarded
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PluginManager"
	)

	static let finishedLoadingNotification = Notification.Name(
		"THOPluginManagerFinishedLoadingPluginsNotification"
	)
	static let scriptCommandsDidChangeNotification = Notification.Name(
		"PluginManagerScriptCommandsDidChangeNotification"
	)

	public var pluginsLoaded: Bool {
		facts.withLock(\.pluginsLoaded)
	}

	/// The loaded plugins themselves. Main actor: a `PluginItem` owns a plugin's
	/// live object and its preferences view.
	@MainActor
	public var loadedPlugins: [PluginItem]? {
		pluginsLoaded ? loadedPluginItems : nil
	}

	@MainActor
	private var loadedPluginItems: [PluginItem] = []

	private let facts = Mutex(PluginFacts())
	private let renderers = Mutex(PluginRendererFacts())
	private let scheduling = Mutex(Scheduling())

	private struct Scheduling {
		var didScheduleLoad = false
		var didScheduleUnload = false
	}

	// MARK: - Retain & Release

	public func loadPlugins() {
		let shouldSchedule = scheduling.withLock { state in
			guard state.didScheduleLoad == false else {
				return false
			}

			state.didScheduleLoad = true
			return true
		}

		guard shouldSchedule else {
			return
		}

		let generation = reserveScriptGeneration()
		Task { [weak self] in
			/* Discovery reads directories and checks code signatures, which is
			 slow enough to keep off the main actor. Loading itself is main-actor
			 work: a plugin's load callback touches AppKit. */
			var discovery = Self.discoverPluginBundles()
			discovery.scriptCatalog = await Self.discoverAppleScripts()
			discovery.scriptGeneration = generation

			await MainActor.run {
				self?.finishLoading(discovery)
			}
		}
	}

	/// Rebuilds the script-command snapshot without blocking command entry or
	/// Settings. Activation and a completed import call this so Finder edits are
	/// picked up while the application remains open.
	public func refreshScriptCommands() {
		let generation = reserveScriptGeneration()
		Task { [weak self] in
			let catalog = await Self.discoverAppleScripts()
			guard let self else { return }

			await publishScriptCatalog(catalog, generation: generation)
		}
	}

	func reserveScriptGeneration() -> UInt64 {
		facts.withLock {
			$0.scripts.generation &+= 1
			return $0.scripts.generation
		}
	}

	@MainActor
	func publishScriptCatalog(_ catalog: PluginScriptCatalog, generation: UInt64) {
		guard scheduling.withLock(\.didScheduleUnload) == false else { return }
		let published = facts.withLock { facts in
			guard facts.scripts.generation == generation else { return false }
			facts.scripts = PluginScriptFacts(catalog: catalog, generation: generation)
			return true
		}
		if published {
			NotificationCenter.default.post(name: Self.scriptCommandsDidChangeNotification, object: self)
		}
	}

	/// Runs the plugins' unload callbacks. Main actor: the callbacks tear down
	/// AppKit state the plugin set up while loading.
	@MainActor
	public func unloadPlugins() {
		let shouldSchedule = scheduling.withLock { state in
			guard state.didScheduleUnload == false else {
				return false
			}

			state.didScheduleUnload = true
			return true
		}

		guard shouldSchedule else {
			return
		}

		let plugins = loadedPluginItems
		loadedPluginItems = []
		facts.withLock { $0 = PluginFacts() }

		/* Withdrawn before the first `pluginWillUnload()`. Bumping the generation
		 under the lock is what reaches a render already in flight: it re-reads
		 the generation before each renderer, so one that has not reached its
		 plugin yet stops there. A call already inside a plugin returns before the
		 tear-down below can start, because that runs on the main actor and a
		 render never holds it. */
		renderers.withLock { facts in
			facts = PluginRendererFacts(generation: facts.generation &+ 1, renderers: [])
		}

		for plugin in plugins {
			plugin.unloadBundle()
		}
	}

	@MainActor
	private func finishLoading(_ discovery: PluginDiscovery) {
		/* Discovery is slow, so the application can be on its way out by the
		 time it lands. Loading now would run every plugin's load callback during
		 termination and leave them there: `unloadPlugins()` has already run and
		 will not run twice. */
		guard scheduling.withLock(\.didScheduleUnload) == false else {
			Self.logger.info("Discarding a plugin load that finished after unloading")
			return
		}

		let host = PluginHostAdapter.makeContext()
		let loadedPlugins = discovery.loadable.compactMap { url in
			guard let bundle = Bundle(url: url) else {
				Self.logger.error(
					"Refusing to load the bundle at “\(url.path, privacy: .public)“ because it could not be opened"
				)
				return nil as PluginItem?
			}

			return PluginItem.load(bundle, host: host)
		}

		loadedPluginItems = loadedPlugins
		publishMessageRenderers(for: loadedPlugins)
		var replacement = PluginFacts(loadedPlugins: loadedPlugins)
		facts.withLock { facts in
			/* A refresh that landed while discovery was still running has
			 already published a newer catalog; discovery's own is then the
			 stale one and only the plugin facts are replaced. */
			replacement.scripts = facts.scripts.generation == discovery.scriptGeneration
				? PluginScriptFacts(catalog: discovery.scriptCatalog, generation: facts.scripts.generation)
				: facts.scripts
			facts = replacement
		}

		NotificationCenter.default.post(name: Self.finishedLoadingNotification, object: self)

		let loadedURLs = Set(loadedPlugins.map(\.bundle.bundleURL))
		let failedNames = discovery.loadable.filter { !loadedURLs.contains($0) }.map(\.lastPathComponent)
		if !failedNames.isEmpty {
			Alerts.alert(
				withMessage: String(localized: .Plugins.loadFailedBody(failedNames.joined(separator: ", "))),
				title: String(localized: .Plugins.loadFailedTitle),
				defaultButton: PromptStrings.Action.confirmation,
				alternateButton: nil
			)
		}
		presentRejectedBundlesAlert(for: discovery.rejected)
		Self.presentObsoleteBundlesAlert(for: discovery.obsolete.compactMap(Bundle.init(url:)))
	}

	// MARK: - Discovery

	private static func discoverPluginBundles() -> PluginDiscovery {
		var discovery = PluginDiscovery()
		var seenBundleIdentifiers = Set<String>()

		for bundle in candidateBundles() {
			guard let bundleIdentifier = bundle.bundleIdentifier else {
				logger.error(
					"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because it declares no bundle identifier"
				)
				continue
			}

			guard seenBundleIdentifiers.insert(bundleIdentifier).inserted else {
				logger.info(
					"Skipping the bundle at “\(bundle.bundlePath, privacy: .public)“ because a bundle with the identifier “\(bundleIdentifier, privacy: .public)“ was already found at an earlier location"
				)
				continue
			}

			guard supportsCurrentPluginProtocol(bundle) else {
				discovery.obsolete.append(bundle.bundleURL)
				continue
			}

			guard isBundledExtension(bundle) || isSignedByThisApplication(bundle) else {
				discovery.rejected.append(bundle.bundleURL)
				continue
			}

			discovery.loadable.append(bundle.bundleURL)
		}

		return discovery
	}

	private static func candidateBundles() -> [Bundle] {
		var searchPaths = [PathInfo.bundledExtensions]
		if let customExtensions = PathInfo.customExtensions {
			searchPaths.append(customExtensions)
		}

		return searchPaths.flatMap { path -> [Bundle] in
			guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: path) else {
				return []
			}

			return filenames.sorted().compactMap { filename in
				guard filename.hasSuffix(ResourceDocumentType.bundleFileExtension) else {
					return nil
				}

				let bundleURL = URL(fileURLWithPath: path, isDirectory: true)
					.appendingPathComponent(filename, isDirectory: true)

				return Bundle(url: bundleURL)
			}
		}
	}

	static let interfaceVersionMetadataKey = "GlasstualPluginInterfaceVersion"
	static let currentInterfaceVersion = 1

	/// A bundle predating the interface-version key declares a host version
	/// instead. The major it has to name is the one the contract itself names.
	static let legacyMinimumMajorVersion = String(
		PluginCompatibility.minimumHostVersion.prefix { $0 != "." }
	)

	static func supportsCurrentPluginProtocol(_ bundle: Bundle) -> Bool {
		if let declaredVersion = bundle.object(forInfoDictionaryKey: interfaceVersionMetadataKey) {
			guard case let .integer(version)? = PropertyListValue(propertyList: declaredVersion),
			      version == currentInterfaceVersion
			else {
				logger.error("Unsupported plugin interface in \(bundle.bundlePath, privacy: .public)")
				return false
			}
			return true
		}

		guard let minimumVersion = bundle.infoDictionary?["MinimumGlasstualVersion"] as? String else {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because it does not declare MinimumGlasstualVersion; the current minimum is \(PluginCompatibility.minimumHostVersion, privacy: .public)"
			)
			return false
		}

		/* Any 8.x.y is accepted, not just the exact minimum: a bundle built
		 against an earlier point release of the same host contract still loads,
		 and the interface-version key above is what pins the contract itself. */
		let components = minimumVersion.split(separator: ".", omittingEmptySubsequences: false)
		guard components.count == 3,
		      components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
		      components.first.map(String.init) == legacyMinimumMajorVersion
		else {
			logger.error(
				"Refusing legacy plugin metadata in \(bundle.bundlePath, privacy: .public): \(minimumVersion, privacy: .public)"
			)
			return false
		}

		return true
	}

	// MARK: - Signature Validation

	private static func isBundledExtension(_ bundle: Bundle) -> Bool {
		let applicationPath = (Bundle.main.bundlePath as NSString).standardizingPath
		let bundlePath = (bundle.bundlePath as NSString).standardizingPath

		return bundlePath.hasPrefix(applicationPath + "/")
	}

	private static let applicationTeamIdentifier: String? = {
		var code: SecCode?
		guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code else {
			return nil
		}
		var staticCode: SecStaticCode?
		guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
		      let staticCode
		else {
			return nil
		}

		return teamIdentifier(of: staticCode)
	}()

	private static func teamIdentifier(of staticCode: SecStaticCode) -> String? {
		var signingInformation: CFDictionary?
		let status = SecCodeCopySigningInformation(
			staticCode,
			SecCSFlags(rawValue: kSecCSSigningInformation),
			&signingInformation
		)

		guard status == errSecSuccess, let signingInformation else {
			return nil
		}

		let information = signingInformation as NSDictionary
		let team = information[kSecCodeInfoTeamIdentifier as String] as? String

		guard let team, team.isEmpty == false else {
			return nil
		}

		return team
	}

	private static func error(withStatus status: OSStatus) -> NSError {
		let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"

		return NSError(
			domain: NSOSStatusErrorDomain,
			code: Int(status),
			userInfo: [NSLocalizedDescriptionKey: message]
		)
	}

	/// Whether `bundle` carries a valid signature from the same Team ID that
	/// signed the running application. Every refusal is logged with its reason.
	static func isSignedByThisApplication(_ bundle: Bundle) -> Bool {
		do {
			try validateSignature(of: bundle)
			return true
		} catch {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its signature is missing or is not ours: \(error.localizedDescription, privacy: .public)"
			)
			return false
		}
	}

	private static func validateSignature(of bundle: Bundle) throws {
		var staticCode: SecStaticCode?
		var status = SecStaticCodeCreateWithPath(
			bundle.bundleURL as CFURL,
			SecCSFlags(rawValue: 0),
			&staticCode
		)

		guard status == errSecSuccess, let staticCode else {
			throw error(withStatus: status)
		}

		let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
		try checkValidity(of: staticCode, flags: validationFlags, requirement: nil)

		guard let team = teamIdentifier(of: staticCode) else {
			throw error(withStatus: errSecCSSignatureUntrusted)
		}

		guard let applicationTeam = applicationTeamIdentifier, team == applicationTeam else {
			throw error(withStatus: errSecCSSignatureUntrusted)
		}

		let requirementString =
			"anchor apple generic and certificate leaf[subject.OU] = \"\(applicationTeam)\""

		var requirement: SecRequirement?
		status = SecRequirementCreateWithString(
			requirementString as CFString,
			SecCSFlags(rawValue: 0),
			&requirement
		)

		guard status == errSecSuccess, let requirement else {
			throw error(withStatus: status)
		}

		try checkValidity(of: staticCode, flags: validationFlags, requirement: requirement)
	}

	private static func checkValidity(
		of staticCode: SecStaticCode,
		flags: SecCSFlags,
		requirement: SecRequirement?
	) throws {
		var validityError: Unmanaged<CFError>?
		let status = SecStaticCodeCheckValidityWithErrors(
			staticCode,
			flags,
			requirement,
			&validityError
		)

		guard status != errSecSuccess else {
			/* The out-parameter is populated on failure only, but release it
			 defensively so a success path can never leak it. */
			validityError?.release()
			return
		}

		guard let validityError else {
			throw error(withStatus: status)
		}

		throw validityError.takeRetainedValue() as Error
	}

	// MARK: - AppleScript Support

	public var supportedAppleScriptCommands: [String] {
		facts.withLock { $0.scripts.commandsByName.keys.sorted() }
	}

	public var supportedAppleScriptCommandsAndPaths: [String: String] {
		facts.withLock { $0.scripts.commandsByName.mapValues(\.url.path) }
	}

	public func script(at url: URL) -> PluginScript? {
		facts.withLock { $0.scripts.commandsByName.values.first { $0.url == url } }
	}

	public var customScriptsURL: URL? {
		facts.withLock(\.scripts.customScriptsURL)
	}

	@concurrent
	private static func discoverAppleScripts() async -> PluginScriptCatalog {
		PluginScriptCatalog.discover(
			customURL: PathInfo.customScriptsURL,
			bundledURL: URL(fileURLWithPath: PathInfo.bundledScripts, isDirectory: true),
			forbiddenCommands: Set(listOfForbiddenCommandNames)
		)
	}

	private static var listOfForbiddenCommandNames: [String] {
		ResourceManager.array(fromResources: "StaticStore", key: "THOPluginManager List of Forbidden Commands")?
			.compactMap(\.string) ?? []
	}

	/// What claims an outgoing command the client has no built-in handler for.
	public func handler(forOutgoingCommand command: String) -> OutgoingCommandHandler {
		facts.withLock { facts in
			let name = command.lowercased()
			return switch (facts.scripts.commandsByName[name], facts.supportedUserInputCommands.contains(name)) {
			case let (.some(script), false): .script(path: script.url.path)
			case (.none, true): .pluginExtension
			case (.some, true): .ambiguous
			case (.none, false): .none
			}
		}
	}

	// MARK: - Message Rendering

	/** `message` after every loaded renderer has had it.

	 Called from the transcript renderer's own queue. The handles are copied out
	 of the lock and called with it released: holding it across a plugin's
	 callback put third-party code between the main actor and a lock the main
	 actor takes, and a renderer that asked the manager anything at all — its own
	 preferences pane, the renderer count — deadlocked on a `Mutex` that does not
	 recurse.

	 What is copied out is the generation as well as the calls, and the generation
	 is read again before each call: `unloadPlugins()` bumps it under the lock
	 before the first `pluginWillUnload()`, so a renderer the render has not
	 reached yet is not called at all. No plugin is rendered through after it has
	 been told it is going away. */
	public func renderingMessage(_ message: String, kind: PluginMessageKind) -> String {
		let published = renderers.withLock { facts in
			(generation: facts.generation, calls: facts.renderers)
		}
		var result = message

		for render in published.calls {
			/* The generation again, before each call rather than once: a publish
			 or an unload that lands here is what says the plugins behind the rest
			 of this list are going away, and the call that has not been made yet
			 is the one that must not reach them. */
			guard renderers.withLock(\.generation) == published.generation else { break }

			guard let returned = render(PluginRenderEvent(message: result, kind: kind)),
			      returned.isEmpty == false
			else {
				continue
			}

			result = returned
		}

		return result
	}

	/// Publishes the renderers among `plugins`, retiring whatever the previous
	/// load published. Loading is the caller; the step is its own so that
	/// standing renderers up does not require a scan of the extension folders.
	@MainActor
	func publishMessageRenderers(for plugins: [PluginItem]) {
		publishMessageRenderers(plugins.compactMap { plugin in
			guard let renderer = plugin.primaryClass as? any PluginMessageRendering else { return nil }
			return { event in renderer.willRenderMessage(event) }
		})
	}

	/** Publishes `calls` as the message renderers, retiring the previous publish.

	 The calls rather than the plugins, because this is also the seam a test
	 stands a renderer up through: the plugin objects are main-actor and a
	 `PluginItem` only comes from a bundle that loaded. */
	func publishMessageRenderers(_ calls: [@Sendable (PluginRenderEvent) -> String?]) {
		renderers.withLock { facts in
			facts = PluginRendererFacts(generation: facts.generation &+ 1, renderers: calls)
		}
	}

	/// Which load the published renderers belong to. Bumped by every publish and
	/// by an unload, so a test can tell one list from the next.
	public var messageRendererGeneration: UInt64 {
		renderers.withLock(\.generation)
	}

	/// How many plugins are currently published as message renderers.
	public var messageRendererCount: Int {
		renderers.withLock(\.renderers.count)
	}

	// MARK: - Extension Information

	public func supportsFeature(_ feature: PluginSupportedFeature) -> Bool {
		facts.withLock { $0.supportedFeatures.contains(feature) }
	}

	public var pluginOutputSuppressionRules: [PluginOutputSuppressionRule] {
		facts.withLock(\.outputSuppressionRules)
	}

	public var supportedUserInputCommands: [String] {
		facts.withLock(\.supportedUserInputCommands)
	}

	public var supportedServerInputCommands: [String] {
		facts.withLock(\.supportedServerInputCommands)
	}

	@MainActor
	public var pluginsWithPreferencePanes: [PluginItem] {
		loadedPluginItems
			.filter { $0.supportsFeature(.preferencePane) }
			.sorted {
				($0.pluginPreferencesPane?.title ?? "")
					.compare($1.pluginPreferencesPane?.title ?? "") == .orderedAscending
			}
	}
}

extension PluginManager {
	// MARK: - Refused Bundles

	@MainActor
	private func presentRejectedBundlesAlert(for rejectedBundles: [URL]) {
		guard rejectedBundles.isEmpty == false else {
			return
		}

		var bundleNames: [String] = []

		for url in rejectedBundles {
			let name = url.lastPathComponent
			if bundleNames.contains(name) == false {
				bundleNames.append(name)
			}
		}

		Alerts.alert(
			withMessage: PromptStrings.Plugin.unsignedBody,
			title: PromptStrings.Plugin.unsignedTitle(pluginNames: bundleNames.joined(separator: ", ")),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	// MARK: - Obsolete Bundles

	@MainActor
	private static func presentObsoleteBundlesAlert(for obsoleteBundles: [Bundle]) {
		guard obsoleteBundles.isEmpty == false else {
			return
		}

		let bundlesName = Bundle.textual_formattedDisplayNames(for: obsoleteBundles)

		Alerts.alert(
			withMessage: String(localized: .Plugins.incompatibleInterfaceBody),
			title: PromptStrings.Plugin.incompatibleTitle(pluginNames: bundlesName),
			defaultButton: PromptStrings.Plugin.incompatibleReminderButtonTitle,
			alternateButton: nil,
			otherButton: PromptStrings.Plugin.viewFilesButtonTitle,
			suppressionKey: nil,
			suppressionText: nil
		) { outcome in
			guard outcome.response == .other else {
				return
			}

			Bundle.textual_openInstallationLocations(for: obsoleteBundles)
			presentObsoleteBundlesAlert(for: obsoleteBundles)
		}
	}
}
