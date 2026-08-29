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
}

/// Everything about the loaded plugins that a caller outside the main actor
/// needs: a plugin's own object stays on the main actor, but which features
/// exist, which commands are subscribed, and the suppression rules are values.
///
/// Message renderers are the exception: they run on the renderer's background
/// queue, so `PluginMessageRendering` is `Sendable` and they are published here.
private nonisolated struct PluginFacts: Sendable { // nonisolated: value
	var pluginsLoaded = false
	var supportedFeatures: PluginSupportedFeature = []
	var outputSuppressionRules: [PluginOutputSuppressionRule] = []
	var supportedUserInputCommands: [String] = []
	var supportedServerInputCommands: [String] = []
	var messageRenderers: [any PluginMessageRendering] = []

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

			if let renderer = plugin.primaryClass as? any PluginMessageRendering {
				messageRenderers.append(renderer)
			}
		}

		pluginsLoaded = true
		supportedUserInputCommands = userInputCommands.sorted()
		supportedServerInputCommands = serverInputCommands.sorted()
	}
}

/// Discovers, validates and loads Glasstual's plugin bundles.
///
/// Only first-party bundles load: one shipped inside the application, or one
/// installed by the user that is signed by the same Team ID. There is no
/// approval prompt — a bundle either satisfies the requirement or is refused
/// and logged.
@objc(THOPluginManager)
public final nonisolated class PluginManager: NSObject, Sendable { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PluginManager"
	)

	static let finishedLoadingNotification = Notification.Name(
		"THOPluginManagerFinishedLoadingPluginsNotification"
	)

	@objc public var pluginsLoaded: Bool {
		facts.withLock(\.pluginsLoaded)
	}

	/// The loaded plugins themselves. Main actor: a `PluginItem` owns a plugin's
	/// live object and its preferences view.
	@MainActor
	@objc public var loadedPlugins: [PluginItem]? {
		pluginsLoaded ? Self.loadedPluginItems : nil
	}

	/// Static because there is one plugin manager and its plugin objects must
	/// live on the main actor, which lets the manager itself stay `Sendable`.
	@MainActor
	private static var loadedPluginItems: [PluginItem] = []

	private let facts = Mutex(PluginFacts())
	private let scheduling = Mutex(Scheduling())

	private struct Scheduling {
		var didScheduleLoad = false
		var didScheduleUnload = false
	}

	// MARK: - Retain & Release

	@objc
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

		Task { [weak self] in
			/* Discovery reads directories and checks code signatures, which is
			 slow enough to keep off the main actor. Loading itself is main-actor
			 work: a plugin's load callback touches AppKit. */
			let discovery = Self.discoverPluginBundles()

			await MainActor.run {
				self?.finishLoading(discovery)
			}
		}
	}

	/// Runs the plugins' unload callbacks. Main actor: the callbacks tear down
	/// AppKit state the plugin set up while loading.
	@MainActor
	@objc
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

		let plugins = Self.loadedPluginItems
		Self.loadedPluginItems = []
		facts.withLock { $0 = PluginFacts() }

		for plugin in plugins {
			plugin.unloadBundle()
		}
	}

	@MainActor
	private func finishLoading(_ discovery: PluginDiscovery) {
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

		Self.loadedPluginItems = loadedPlugins
		let newFacts = PluginFacts(loadedPlugins: loadedPlugins)
		facts.withLock { $0 = newFacts }

		NotificationCenter.default.post(name: Self.finishedLoadingNotification, object: self)

		presentRejectedBundlesAlert(for: discovery.rejected)
		Self.presentObsoleteBundlesAlert(for: discovery.obsolete.compactMap(Bundle.init(url:)))
	}
}

nonisolated extension PluginManager { // nonisolated: pure
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

			return filenames.compactMap { filename in
				guard filename.hasSuffix(ResourceDocumentType.bundleFileExtension) else {
					return nil
				}

				let bundleURL = URL(fileURLWithPath: path, isDirectory: true)
					.appendingPathComponent(filename, isDirectory: true)

				return Bundle(url: bundleURL)
			}
		}
	}

	private static func supportsCurrentPluginProtocol(_ bundle: Bundle) -> Bool {
		guard let minimumVersion = bundle.infoDictionary?["MinimumGlasstualVersion"] as? String else {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because it does not declare MinimumGlasstualVersion; the current minimum is \(PluginCompatibility.minimumHostVersion, privacy: .public)"
			)
			return false
		}

		guard minimumVersion.compare(
			PluginCompatibility.minimumHostVersion,
			options: .numeric
		) != .orderedAscending else {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its minimum Glasstual version \(minimumVersion, privacy: .public) is older than the supported plugin protocol \(PluginCompatibility.minimumHostVersion, privacy: .public)"
			)
			return false
		}

		return true
	}
}

nonisolated extension PluginManager { // nonisolated: pure
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

		TDCAlert.alert(
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

		TDCAlert.alert(
			withMessage: PromptStrings.Plugin.incompatibleBody(
				minimumVersion: PluginCompatibility.minimumHostVersion
			),
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

public nonisolated extension PluginManager { // nonisolated: pure
	// MARK: - AppleScript Support

	@objc var supportedAppleScriptCommands: [String] {
		supportedAppleScriptCommands(returnPathInfo: false) as? [String] ?? []
	}

	@objc var supportedAppleScriptCommandsAndPaths: [String: String] {
		supportedAppleScriptCommands(returnPathInfo: true) as? [String: String] ?? [:]
	}

	private func supportedAppleScriptCommands(returnPathInfo: Bool) -> Any {
		let forbiddenCommands = listOfForbiddenCommandNames

		var scriptLocations: [(path: String, isBundled: Bool)] = []
		if let customScripts = PathInfo.customScripts {
			scriptLocations.append((customScripts, false))
		}
		scriptLocations.append((PathInfo.bundledScripts, true))

		let returnValue: NSObject = if returnPathInfo {
			NSMutableDictionary()
		} else {
			NSMutableArray()
		}

		for location in scriptLocations {
			let path = location.path
			guard let pathFiles = try? FileManager.default.contentsOfDirectory(atPath: path) else {
				continue
			}

			for file in pathFiles where file.hasPrefix(".") == false {
				let filePath = (path as NSString).appendingPathComponent(file)
				let fileExtension = (file as NSString).pathExtension.lowercased()
				let fileWithoutExtension = (file as NSString).deletingPathExtension
				let command = fileWithoutExtension.lowercased()

				let executable = FileManager.default.isExecutableFile(atPath: filePath)

				if executable == false,
				   fileExtension != ResourceDocumentType.scriptFilenameExtension.lowercased()
				{
					if location.isBundled {
						Self.logger.error(
							"Bundled script resource “\(file, privacy: .public)“ is neither AppleScript nor executable"
						)
					} else {
						Self.logger.info(
							"Ignoring unsupported custom script file “\(file, privacy: .public)“"
						)
					}
					continue
				}

				if forbiddenCommands.contains(command) {
					Self.logger.info(
						"Ignoring script command “\(fileWithoutExtension, privacy: .public)“ because its command name is reserved"
					)
					continue
				}

				if returnPathInfo, let dictionary = returnValue as? NSMutableDictionary {
					if dictionary.object(forKey: command) == nil {
						dictionary.setObject(filePath, forKey: command as NSString)
					}
				} else if let array = returnValue as? NSMutableArray {
					if array.contains(command) == false {
						array.add(command)
					}
				}
			}
		}

		return returnValue
	}

	private var listOfForbiddenCommandNames: [String] {
		ResourceManager.array(fromResources: "StaticStore", key: "THOPluginManager List of Forbidden Commands")
			as? [String] ?? []
	}

	@objc(findHandlerForOutgoingCommand:path:isScript:isExtension:)
	func findHandler(
		forOutgoingCommand command: String,
		path: AutoreleasingUnsafeMutablePointer<NSString?>?,
		isScript: UnsafeMutablePointer<ObjCBool>?,
		isExtension: UnsafeMutablePointer<ObjCBool>?
	) {
		path?.pointee = nil
		isScript?.pointee = false
		isExtension?.pointee = false

		let scriptPaths = supportedAppleScriptCommandsAndPaths

		for (scriptCommand, scriptPath) in scriptPaths {
			guard scriptCommand == command else {
				continue
			}

			path?.pointee = scriptPath as NSString
			isScript?.pointee = true
			return
		}

		if supportedUserInputCommands.contains(command) {
			isExtension?.pointee = true
		}
	}
}

public nonisolated extension PluginManager { // nonisolated: pure
	// MARK: - Extension Information

	func supportsFeature(_ feature: PluginSupportedFeature) -> Bool {
		facts.withLock { $0.supportedFeatures.contains(feature) }
	}

	var pluginOutputSuppressionRules: [PluginOutputSuppressionRule] {
		facts.withLock(\.outputSuppressionRules)
	}

	/// The plugins that rewrite message bodies, in load order. Published apart
	/// from `loadedPlugins` because the renderer calls them off the main actor.
	var messageRenderers: [any PluginMessageRendering] {
		facts.withLock(\.messageRenderers)
	}

	@objc var supportedUserInputCommands: [String] {
		facts.withLock(\.supportedUserInputCommands)
	}

	@objc var supportedServerInputCommands: [String] {
		facts.withLock(\.supportedServerInputCommands)
	}

	@MainActor
	@objc var pluginsWithPreferencePanes: [PluginItem] {
		Self.loadedPluginItems
			.filter { $0.supportsFeature(.preferencePane) }
			.sorted {
				($0.pluginPreferencesPaneMenuItemTitle ?? "")
					.compare($1.pluginPreferencesPaneMenuItemTitle ?? "") == .orderedAscending
			}
	}
}
