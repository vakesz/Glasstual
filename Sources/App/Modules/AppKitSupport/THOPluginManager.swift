/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

private enum PluginApprovalState: UInt {
	case unknown = 0
	case approved
	case declined
}

private final class PluginPendingApproval: NSObject {
	let bundle: Bundle
	let teamIdentifier: String

	init(bundle: Bundle, teamIdentifier: String) {
		self.bundle = bundle
		self.teamIdentifier = teamIdentifier
	}
}

/// Carries the approval workflow across the plugin queue and the main actor.
/// Access remains serialized by those queues; the envelope prevents Swift from
/// treating its legacy Objective-C collection as independently transferable.
private final class PluginApprovalTransfer: @unchecked Sendable {
	weak var manager: PluginManager?
	let pendingApprovals: [PluginPendingApproval]
	let loadedPlugins: NSMutableArray

	init(
		manager: PluginManager,
		pendingApprovals: [PluginPendingApproval],
		loadedPlugins: NSMutableArray
	) {
		self.manager = manager
		self.pendingApprovals = pendingApprovals
		self.loadedPlugins = loadedPlugins
	}
}

private final class PluginLoadResult: Sendable {
	let plugin = Mutex<PluginItem?>(nil)
}

/// An immutable view of every plugin capability published to the rest of the app.
/// Plugin discovery builds this value off the main actor after every plugin has
/// completed its main-actor lifecycle setup, then replaces it as one transaction.
private struct PluginRegistrySnapshot: Sendable {
	static let notLoaded = Self()

	let pluginsLoaded: Bool
	let loadedPlugins: [PluginItem]?
	let supportedFeatures: PluginSupportedFeature
	let outputSuppressionRules: [PluginOutputSuppressionRule]
	let supportedUserInputCommands: [String]
	let supportedServerInputCommands: [String]
	let pluginsWithPreferencePanes: [PluginItem]

	private init() {
		pluginsLoaded = false
		loadedPlugins = nil
		supportedFeatures = []
		outputSuppressionRules = []
		supportedUserInputCommands = []
		supportedServerInputCommands = []
		pluginsWithPreferencePanes = []
	}

	init(loadedPlugins: [PluginItem]) {
		var supportedFeatures: PluginSupportedFeature = []
		var outputSuppressionRules: [PluginOutputSuppressionRule] = []
		var userInputCommands = Set<String>()
		var serverInputCommands = Set<String>()
		var pluginsWithPreferencePanes: [PluginItem] = []

		for plugin in loadedPlugins {
			supportedFeatures.formUnion(plugin.supportedFeatures)

			if plugin.supportsFeature(.outputSuppressionRules),
			   let rules = plugin.outputSuppressionRules
			{
				outputSuppressionRules.append(contentsOf: rules)
			}

			if plugin.supportsFeature(.subscribedUserInputCommands),
			   let commands = plugin.supportedUserInputCommands
			{
				userInputCommands.formUnion(commands)
			}

			if plugin.supportsFeature(.subscribedServerInputCommands),
			   let commands = plugin.supportedServerInputCommands
			{
				serverInputCommands.formUnion(commands)
			}

			if plugin.supportsFeature(.preferencePane) {
				pluginsWithPreferencePanes.append(plugin)
			}
		}

		pluginsWithPreferencePanes.sort {
			($0.pluginPreferencesPaneMenuItemTitle ?? "")
				.compare($1.pluginPreferencesPaneMenuItemTitle ?? "") == .orderedAscending
		}

		pluginsLoaded = true
		self.loadedPlugins = loadedPlugins
		self.supportedFeatures = supportedFeatures
		self.outputSuppressionRules = outputSuppressionRules
		supportedUserInputCommands = userInputCommands.sorted()
		supportedServerInputCommands = serverInputCommands.sorted()
		self.pluginsWithPreferencePanes = pluginsWithPreferencePanes
	}
}

@objc(THOPluginManager)
public final class PluginManager: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PluginManager"
	)

	private static let approvalsDefaultsKey = "Plugin Approvals"
	private static let approvalTeamIdentifierKey = "teamIdentifier"
	private static let approvalDateKey = "approvedDate"
	private static let approvalApprovedKey = "approved"
	static let finishedLoadingNotification = Notification.Name(
		"THOPluginManagerFinishedLoadingPluginsNotification"
	)

	@objc public var pluginsLoaded: Bool {
		registry.withLock { $0.pluginsLoaded }
	}

	@objc public var loadedPlugins: [PluginItem]? {
		registry.withLock { $0.loadedPlugins }
	}

	private var obsoleteBundles: [Bundle]?
	private var rejectedBundles: [Bundle]?
	private let registry = Mutex(PluginRegistrySnapshot.notLoaded)

	private var didScheduleLoad = false
	private var didScheduleUnload = false
	private let schedulingLock = NSLock()

	// MARK: - Retain & Release

	@objc
	public func loadPlugins() {
		let shouldSchedule = schedulingLock.withLock {
			guard didScheduleLoad == false else {
				return false
			}

			didScheduleLoad = true
			return true
		}

		guard shouldSchedule else {
			return
		}

		performAsynchronously(on: PluginDispatcher.dispatchQueue()) { [weak self] in
			self?.loadPluginsInternal()
		}
	}

	@objc
	public func unloadPlugins() {
		let shouldSchedule = schedulingLock.withLock {
			guard didScheduleUnload == false else {
				return false
			}

			didScheduleUnload = true
			return true
		}

		guard shouldSchedule else {
			return
		}

		performAsynchronously(on: PluginDispatcher.dispatchQueue()) { [weak self] in
			self?.unloadPluginsInternal()
		}
	}

	private func loadPluginsInternal() {
		var loadedPlugins: [PluginItem] = []
		var seenBundleIdentifiers = Set<String>()
		var obsoleteBundles: [Bundle] = []
		var rejectedBundles: [Bundle] = []
		var pendingApprovals: [PluginPendingApproval] = []

		for bundle in discoveredPluginBundles() {
			guard let bundleIdentifier = bundle.bundleIdentifier else {
				continue
			}

			guard seenBundleIdentifiers.insert(bundleIdentifier).inserted else {
				Self.logger.info(
					"Skipping the bundle at “\(bundle.bundlePath, privacy: .public)“ because a bundle with the identifier “\(bundleIdentifier, privacy: .public)“ was already found at an earlier location"
				)
				continue
			}

			guard supportsCurrentPluginProtocol(bundle) else {
				obsoleteBundles.append(bundle)
				continue
			}

			if isBundledExtension(bundle) == false {
				var teamIdentifier: NSString?
				var validationError: NSError?

				if validateSignature(
					of: bundle,
					teamIdentifier: &teamIdentifier,
					error: &validationError
				) == false {
					Self.logger.error(
						"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its signature is missing or invalid: \(validationError?.localizedDescription ?? "", privacy: .public)"
					)
					rejectedBundles.append(bundle)
					continue
				}

				guard let teamIdentifier = teamIdentifier as String? else {
					rejectedBundles.append(bundle)
					continue
				}

				let approvalState = approvalState(
					forBundleIdentifier: bundleIdentifier,
					teamIdentifier: teamIdentifier
				)

				if approvalState == .declined {
					Self.logger.info(
						"Not loading the bundle at “\(bundle.bundlePath, privacy: .public)“ because the user declined it"
					)
					continue
				}

				if approvalState == .unknown {
					pendingApprovals.append(
						PluginPendingApproval(bundle: bundle, teamIdentifier: teamIdentifier)
					)
					continue
				}
			}

			if let plugin = loadBundleAsPlugin(bundle) {
				loadedPlugins.append(plugin)
			}
		}

		self.obsoleteBundles = obsoleteBundles
		self.rejectedBundles = rejectedBundles

		if pendingApprovals.isEmpty {
			finishLoading(with: loadedPlugins)
			return
		}

		let approvalTransfer = PluginApprovalTransfer(
			manager: self,
			pendingApprovals: pendingApprovals,
			loadedPlugins: NSMutableArray(array: loadedPlugins)
		)

		performAsynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				approvalTransfer.manager?.promptForPendingApprovals(
					approvalTransfer.pendingApprovals,
					at: 0,
					loadedPlugins: approvalTransfer.loadedPlugins
				)
			}
		}
	}

	private func discoveredPluginBundles() -> [Bundle] {
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

	private func supportsCurrentPluginProtocol(_ bundle: Bundle) -> Bool {
		guard let minimumVersion = bundle.infoDictionary?["MinimumGlasstualVersion"] as? String else {
			Self.logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because it does not declare MinimumGlasstualVersion; the current minimum is \(PluginCompatibility.minimumHostVersion, privacy: .public)"
			)
			return false
		}

		guard minimumVersion.compare(
			PluginCompatibility.minimumHostVersion,
			options: .numeric
		) != .orderedAscending else {
			Self.logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its minimum Glasstual version \(minimumVersion, privacy: .public) is older than the supported plugin protocol \(PluginCompatibility.minimumHostVersion, privacy: .public)"
			)
			return false
		}

		return true
	}

	private func loadBundleAsPlugin(_ bundle: Bundle) -> PluginItem? {
		let result = PluginLoadResult()

		performSynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				let plugin = PluginItem()

				guard plugin.loadBundle(bundle, host: PluginHostAdapter.makeContext()) else {
					return
				}

				result.plugin.withLock { $0 = plugin }
			}
		}

		guard let plugin = result.plugin.withLock({ $0 }) else {
			return nil
		}

		return plugin
	}

	private func finishLoading(with loadedPlugins: [PluginItem]) {
		let snapshot = PluginRegistrySnapshot(loadedPlugins: loadedPlugins)
		registry.withLock { $0 = snapshot }

		performAsynchronouslyOnMainQueue { [weak self] in
			guard let self else {
				return
			}

			checkForRejectedBundles()
			checkForObsoleteBundles()

			NotificationCenter.default.post(
				name: Self.finishedLoadingNotification,
				object: self
			)
		}
	}

	private func unloadPluginsInternal() {
		let plugins = registry.withLock { snapshot in
			let plugins = snapshot.loadedPlugins ?? []
			snapshot = .notLoaded
			return plugins
		}

		performSynchronouslyOnMainQueue {
			MainActor.assumeIsolated {
				for plugin in plugins {
					plugin.unloadBundle()
				}
			}
		}
	}
}

extension PluginManager {
	// MARK: - Signature Validation

	private func isBundledExtension(_ bundle: Bundle) -> Bool {
		let applicationPath = (Bundle.main.bundlePath as NSString).standardizingPath
		let bundlePath = (bundle.bundlePath as NSString).standardizingPath

		return bundlePath.hasPrefix(applicationPath + "/")
	}

	private nonisolated static let applicationTeamIdentifier: String? = {
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
	}()

	private static func error(withStatus status: OSStatus) -> NSError {
		let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"

		return NSError(
			domain: NSOSStatusErrorDomain,
			code: Int(status),
			userInfo: [NSLocalizedDescriptionKey: message]
		)
	}

	@discardableResult
	private func validateSignature(
		of bundle: Bundle,
		teamIdentifier: AutoreleasingUnsafeMutablePointer<NSString?>?,
		error: AutoreleasingUnsafeMutablePointer<NSError?>?
	) -> Bool {
		teamIdentifier?.pointee = nil
		error?.pointee = nil

		var staticCode: SecStaticCode?
		var status = SecStaticCodeCreateWithPath(
			bundle.bundleURL as CFURL,
			SecCSFlags(rawValue: 0),
			&staticCode
		)

		if status != errSecSuccess || staticCode == nil {
			error?.pointee = Self.error(withStatus: status)
			return false
		}

		guard let staticCode else {
			error?.pointee = Self.error(withStatus: status)
			return false
		}

		let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)

		var validityError: Unmanaged<CFError>?
		status = SecStaticCodeCheckValidityWithErrors(staticCode, validationFlags, nil, &validityError)

		if status != errSecSuccess {
			if let validityError {
				error?.pointee = validityError.takeRetainedValue() as Error as NSError
			} else {
				error?.pointee = Self.error(withStatus: status)
			}
			return false
		}

		var signingInformation: CFDictionary?
		status = SecCodeCopySigningInformation(
			staticCode,
			SecCSFlags(rawValue: kSecCSSigningInformation),
			&signingInformation
		)

		guard status == errSecSuccess, let signingInformation else {
			error?.pointee = Self.error(withStatus: status)
			return false
		}

		let information = signingInformation as NSDictionary
		let team = information[kSecCodeInfoTeamIdentifier as String] as? String

		guard let team, team.isEmpty == false else {
			error?.pointee = Self.error(withStatus: errSecCSSignatureUntrusted)
			return false
		}

		let applicationTeam = Self.applicationTeamIdentifier
		let sameTeam = (applicationTeam != nil && team == applicationTeam)

		guard sameTeam, let applicationTeam else {
			error?.pointee = Self.error(withStatus: errSecCSSignatureUntrusted)
			return false
		}

		let requirementString =
			"anchor apple generic and certificate leaf[subject.OU] = \"\(applicationTeam)\""

		var requirement: SecRequirement?
		status = SecRequirementCreateWithString(
			requirementString as CFString,
			SecCSFlags(rawValue: 0),
			&requirement
		)

		if status != errSecSuccess || requirement == nil {
			error?.pointee = Self.error(withStatus: status)
			return false
		}

		guard let requirement else {
			error?.pointee = Self.error(withStatus: status)
			return false
		}

		validityError = nil
		status = SecStaticCodeCheckValidityWithErrors(
			staticCode,
			validationFlags,
			requirement,
			&validityError
		)

		if status != errSecSuccess {
			if let validityError {
				error?.pointee = validityError.takeRetainedValue() as Error as NSError
			} else {
				error?.pointee = Self.error(withStatus: status)
			}
			return false
		}

		if let validityError {
			_ = validityError.takeRetainedValue()
		}

		teamIdentifier?.pointee = team as NSString

		return true
	}
}

extension PluginManager {
	// MARK: - Approvals

	private static var approvals: [String: [String: Any]] {
		TextualUserDefaults.shared().dictionary(forKey: approvalsDefaultsKey)
			as? [String: [String: Any]] ?? [:]
	}

	private func approvalState(
		forBundleIdentifier bundleIdentifier: String,
		teamIdentifier: String
	) -> PluginApprovalState {
		guard let record = Self.approvals[bundleIdentifier] else {
			return .unknown
		}

		guard (record[Self.approvalTeamIdentifierKey] as? String) == teamIdentifier else {
			return .unknown
		}

		let approved: Bool = if let number = record[Self.approvalApprovedKey] as? NSNumber {
			number.boolValue
		} else if let bool = record[Self.approvalApprovedKey] as? Bool {
			bool
		} else {
			false
		}

		return approved ? .approved : .declined
	}

	private func recordApproval(
		_ approved: Bool,
		forBundleIdentifier bundleIdentifier: String,
		teamIdentifier: String
	) {
		var approvals = Self.approvals

		approvals[bundleIdentifier] = [
			Self.approvalTeamIdentifierKey: teamIdentifier,
			Self.approvalDateKey: Date(),
			Self.approvalApprovedKey: approved,
		]

		TextualUserDefaults.shared().set(approvals, forKey: Self.approvalsDefaultsKey)
	}

	@objc
	public static func resetApprovals() {
		TextualUserDefaults.shared().removeObject(forKey: approvalsDefaultsKey)
	}

	@MainActor
	private func promptForPendingApprovals(
		_ pendingApprovals: [PluginPendingApproval],
		at index: Int,
		loadedPlugins: NSMutableArray
	) {
		if index >= pendingApprovals.count {
			let plugins = loadedPlugins.compactMap { $0 as? PluginItem }

			performAsynchronously(on: PluginDispatcher.dispatchQueue()) { [weak self] in
				self?.finishLoading(with: plugins)
			}

			return
		}

		let pending = pendingApprovals[index]
		let bundle = pending.bundle
		let bundleIdentifier = bundle.bundleIdentifier ?? ""
		let teamIdentifier = pending.teamIdentifier

		var displayName = bundle.textualDisplayName ?? ""
		if displayName.isEmpty {
			displayName = (bundle.bundlePath as NSString).lastPathComponent
		}

		let tildePath = (bundle.bundleURL as NSURL).textualStandardizedTildePath ?? bundle.bundlePath
		guard let window = NSObject.applicationController().mainWindow else {
			return
		}

		TDCAlert.alertSheet(
			with: window,
			body: PromptStrings.Plugin.loadApprovalBody(
				displayName: displayName,
				bundleIdentifier: bundleIdentifier,
				teamIdentifier: teamIdentifier,
				location: tildePath
			),
			title: PromptStrings.Plugin.loadApprovalTitle(displayName: displayName),
			defaultButton: PromptStrings.Plugin.loadDeniedButtonTitle,
			alternateButton: PromptStrings.Plugin.loadButtonTitle,
			otherButton: nil
		) { [weak self] buttonClicked, _, _ in
			guard let self else {
				return
			}

			let approved = (buttonClicked == .alternate)

			recordApproval(
				approved,
				forBundleIdentifier: bundleIdentifier,
				teamIdentifier: teamIdentifier
			)

			performAsynchronously(on: PluginDispatcher.dispatchQueue()) {
				if approved {
					if let plugin = self.loadBundleAsPlugin(bundle) {
						loadedPlugins.add(plugin)
					}
				} else {
					Self.logger.info(
						"Not loading the bundle at “\(bundle.bundlePath, privacy: .public)“ because the user declined it"
					)
				}

				performAsynchronouslyOnMainQueue {
					MainActor.assumeIsolated {
						self.promptForPendingApprovals(
							pendingApprovals,
							at: index + 1,
							loadedPlugins: loadedPlugins
						)
					}
				}
			}
		}
	}

	// MARK: - Rejected Bundles

	private func checkForRejectedBundles() {
		guard let rejectedBundles, rejectedBundles.isEmpty == false else {
			return
		}

		var bundleNames: [String] = []

		for bundle in rejectedBundles {
			let name = (bundle.bundlePath as NSString).lastPathComponent
			if bundleNames.contains(name) == false {
				bundleNames.append(name)
			}
		}

		let bundlesName = bundleNames.joined(separator: ", ")

		self.rejectedBundles = nil

		_ = TDCAlert.alert(
			withMessage: PromptStrings.Plugin.unsignedBody,
			title: PromptStrings.Plugin.unsignedTitle(pluginNames: bundlesName),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}
}

extension PluginManager {
	// MARK: - AppleScript Support

	@objc public var supportedAppleScriptCommands: [String] {
		supportedAppleScriptCommands(returnPathInfo: false) as? [String] ?? []
	}

	@objc public var supportedAppleScriptCommandsAndPaths: [String: String] {
		supportedAppleScriptCommands(returnPathInfo: true) as? [String: String] ?? [:]
	}

	private func supportedAppleScriptCommands(returnPathInfo: Bool) -> Any {
		let forbiddenCommands = listOfForbiddenCommandNames

		var scriptPaths: [String] = []
		if let customScripts = PathInfo.customScripts {
			scriptPaths.append(customScripts)
		}
		scriptPaths.append(PathInfo.bundledScripts)

		let returnValue: NSObject = if returnPathInfo {
			NSMutableDictionary()
		} else {
			NSMutableArray()
		}

		for path in scriptPaths {
			guard let pathFiles = try? FileManager.default.contentsOfDirectory(atPath: path) else {
				continue
			}

			for file in pathFiles {
				let filePath = (path as NSString).appendingPathComponent(file)
				let fileExtension = (file as NSString).pathExtension
				let fileWithoutExtension = (file as NSString).deletingPathExtension
				let command = fileWithoutExtension.lowercased()

				let executable = FileManager.default.isExecutableFile(atPath: filePath)

				if executable == false,
				   fileExtension != ResourceDocumentType.scriptFilenameExtension
				{
					Self.logger.info(
						"WARNING: File “\(file, privacy: .public)“ found in unsupervised script folder but it isn't AppleScript or an executable. It will be ignored."
					)
					continue
				}

				if forbiddenCommands.contains(command) {
					Self.logger.info(
						"WARNING: The command “\(fileWithoutExtension, privacy: .public)“ exists as a script file, but it is being ignored because the command name is forbidden."
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

	// MARK: - Obsolete Bundles

	private func checkForObsoleteBundles() {
		guard let obsoleteBundles, obsoleteBundles.isEmpty == false else {
			return
		}

		presentObsoleteBundlesAlert(for: obsoleteBundles)
	}

	private func presentObsoleteBundlesAlert(for thirdPartyBundles: [Bundle]) {
		let bundlesName = Bundle.textual_formattedDisplayNames(for: thirdPartyBundles)

		_ = TDCAlert.alert(
			withMessage: PromptStrings.Plugin.incompatibleBody(
				minimumVersion: PluginCompatibility.minimumHostVersion
			),
			title: PromptStrings.Plugin.incompatibleTitle(pluginNames: bundlesName),
			defaultButton: PromptStrings.Plugin.incompatibleReminderButtonTitle,
			alternateButton: nil,
			otherButton: PromptStrings.Plugin.viewFilesButtonTitle,
			suppressionKey: nil,
			suppressionText: nil
		) { [weak self] buttonClicked, _, _ in
			guard buttonClicked == .other else {
				return
			}

			Bundle.textual_openInstallationLocations(for: thirdPartyBundles)
			self?.presentObsoleteBundlesAlert(for: thirdPartyBundles)
		}
	}

	@objc(findHandlerForOutgoingCommand:path:isScript:isExtension:)
	public func findHandler(
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

public extension PluginManager {
	// MARK: - Extension Information

	func supportsFeature(_ feature: PluginSupportedFeature) -> Bool {
		registry.withLock { $0.supportedFeatures.contains(feature) }
	}

	var pluginOutputSuppressionRules: [PluginOutputSuppressionRule] {
		registry.withLock { $0.outputSuppressionRules }
	}

	@objc var supportedUserInputCommands: [String] {
		registry.withLock { $0.supportedUserInputCommands }
	}

	@objc var supportedServerInputCommands: [String] {
		registry.withLock { $0.supportedServerInputCommands }
	}

	@objc var pluginsWithPreferencePanes: [PluginItem] {
		registry.withLock { $0.pluginsWithPreferencePanes }
	}
}
