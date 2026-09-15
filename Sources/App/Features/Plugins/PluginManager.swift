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
import Synchronization

/// Everything about the loaded plugins that a caller outside the main actor
/// needs: a plugin's own object stays on the main actor, but which features
/// exist and which commands are subscribed are values.
private nonisolated struct PluginFacts: Sendable { // nonisolated: value
	var pluginsLoaded = false
	var supportedFeatures: PluginSupportedFeature = []
	var supportedUserInputCommands: [String] = []
	var supportedServerInputCommands: [String] = []
	var scripts = PluginScriptCatalog()
	/** Which scan the published catalog came from.

	 Discovery and a refresh both run off the main actor and can land in either
	 order, so a scan whose generation is no longer the reserved one has been
	 overtaken and its catalog is dropped. */
	var scriptGeneration: UInt64 = 0

	init() {}

	@MainActor
	init(loadedPlugins: [PluginItem]) {
		var userInputCommands = Set<String>()
		var serverInputCommands = Set<String>()

		for plugin in loadedPlugins {
			supportedFeatures.formUnion(plugin.supportedFeatures)
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

/// Loads the plugin bundles `PluginDiscovery` finds and
/// `PluginBundleValidation` accepts.
///
/// Only first-party bundles load: one shipped inside the application, or one
/// installed by the user that is signed by the same Team ID. There is no
/// approval prompt — a bundle either satisfies the requirement or is refused
/// and logged.
///
/// Nonisolated because the transcript renderer reads it off the main actor:
/// `PluginDispatcher.willRenderMessage` runs on the renderer's own queue, so
/// the manager cannot move onto the main actor with the plugin objects it
/// loads. What that caller reads is the `Mutex`-guarded `PluginFacts` value
/// below, and — for the one callback that reaches a plugin off the main actor
/// — `renderingMessage(_:kind:)`, which calls the published renderers under
/// the lock that retires them. The plugin objects themselves stay in
/// `loadedPluginItems`, which is main-actor.
public final nonisolated class PluginManager: Sendable { // nonisolated: guarded
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
	var loadedPlugins: [PluginItem]? {
		pluginsLoaded ? loadedPluginItems : nil
	}

	@MainActor
	private var loadedPluginItems: [PluginItem] = []

	private let facts = Mutex(PluginFacts())
	private let renderers = Mutex(PluginRendererFacts())

	/** How far the manager has got.

	 Main actor, because every step that moves it is main-actor work: loading
	 runs the plugins' load callbacks, unloading runs their tear-down, and a
	 discovery that lands after `unloaded` is dropped rather than loaded into an
	 application on its way out. */
	@MainActor
	private var lifecycle = Lifecycle.idle

	/// The discovery `loadPlugins()` started, cancelled by `unloadPlugins()` so
	/// a scan still running at termination stops rather than landing late.
	@MainActor
	private var loadingTask: Task<Void, Never>?

	private enum Lifecycle {
		case idle
		case loading
		case unloaded
	}

	// MARK: - Retain & Release

	@MainActor
	public func loadPlugins() {
		guard lifecycle == .idle else {
			return
		}

		lifecycle = .loading

		let generation = reserveScriptGeneration()
		loadingTask = Task { [weak self] in
			/* Discovery reads directories and checks code signatures, and the
			 script scan reads directories too: both run off the main actor, side
			 by side. Loading itself is main-actor work — a plugin's load callback
			 touches AppKit — and this task is main-actor, so it resumes here. */
			async let bundles = PluginDiscovery.scan()
			async let scripts = Self.discoverAppleScripts()
			var discovery = await bundles
			discovery.scriptCatalog = await scripts
			discovery.scriptGeneration = generation

			guard Task.isCancelled == false else { return }
			self?.finishLoading(discovery)
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
			$0.scriptGeneration &+= 1
			return $0.scriptGeneration
		}
	}

	@MainActor
	func publishScriptCatalog(_ catalog: PluginScriptCatalog, generation: UInt64) {
		guard lifecycle != .unloaded else { return }
		let published = facts.withLock { facts in
			guard facts.scriptGeneration == generation else { return false }
			facts.scripts = catalog
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
		guard lifecycle != .unloaded else {
			return
		}

		lifecycle = .unloaded
		loadingTask?.cancel()
		loadingTask = nil

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
		guard lifecycle != .unloaded else {
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
			replacement.scriptGeneration = facts.scriptGeneration
			replacement.scripts = facts.scriptGeneration == discovery.scriptGeneration
				? discovery.scriptCatalog
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
	 of the lock and called with it released: `Mutex` does not recurse, so a
	 renderer that asks the manager anything at all — its own preferences pane,
	 the renderer count — would deadlock against a lock held across its own
	 callback.

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

	public var supportedUserInputCommands: [String] {
		facts.withLock(\.supportedUserInputCommands)
	}

	public var supportedServerInputCommands: [String] {
		facts.withLock(\.supportedServerInputCommands)
	}

	@MainActor
	var pluginsWithPreferencePanes: [PluginItem] {
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
