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
import os
import Security

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

	@objc public private(set) var pluginsLoaded = false
	@objc public private(set) var loadedPlugins: [PluginItem]?

	private var obsoleteBundles: [Bundle]?
	private var rejectedBundles: [Bundle]?
	private var supportedFeatures: THOPluginItemSupportedFeature = []

	private var didScheduleLoad = false
	private var didScheduleUnload = false

	private var cachedOutputSuppressionRules: [THOPluginOutputSuppressionRule]?
	private var cachedUserInputCommands: [String]?
	private var cachedServerInputCommands: [String]?
	private var cachedPluginsWithPreferencePanes: [PluginItem]?

	// MARK: - Retain & Release

	@objc
	public func loadPlugins() {
		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		guard didScheduleLoad == false else {
			return
		}

		didScheduleLoad = true

		XRPerformBlockAsynchronouslyOnQueue(PluginDispatcher.dispatchQueue()) { [weak self] in
			self?.loadPluginsInternal()
		}
	}

	@objc
	public func unloadPlugins() {
		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		guard didScheduleUnload == false else {
			return
		}

		didScheduleUnload = true

		XRPerformBlockAsynchronouslyOnQueue(PluginDispatcher.dispatchQueue()) { [weak self] in
			self?.unloadPluginsInternal()
		}
	}

	private func loadPluginsInternal() {
		var loadedPlugins: [PluginItem] = []
		var bundlesToLoad: [String] = []
		var seenBundles: [String] = []
		var obsoleteBundles: [Bundle] = []
		var rejectedBundles: [Bundle] = []
		var pendingApprovals: [PluginPendingApproval] = []

		var pathsToLoad: [String] = [PathInfo.bundledExtensions]
		if let customExtensions = PathInfo.customExtensions {
			pathsToLoad.append(customExtensions)
		}

		for path in pathsToLoad {
			guard let pathFiles = try? FileManager.default.contentsOfDirectory(atPath: path) else {
				continue
			}

			for file in pathFiles {
				guard file.hasSuffix(TPCResourceManagerBundleDocumentTypeExtension) else {
					continue
				}

				bundlesToLoad.append((path as NSString).appendingPathComponent(file))
			}
		}

		for bundlePath in bundlesToLoad {
			guard let bundle = Bundle(path: bundlePath),
			      let bundleIdentifier = bundle.bundleIdentifier
			else {
				continue
			}

			if seenBundles.contains(bundleIdentifier) {
				Self.logger.info(
					"Skipping the bundle at “\(bundle.bundlePath, privacy: .public)“ because a bundle with the identifier “\(bundleIdentifier, privacy: .public)“ was already found at an earlier location"
				)
				continue
			}

			seenBundles.append(bundleIdentifier)

			let infoDictionary = bundle.infoDictionary
			guard let comparisonVersion = infoDictionary?["MinimumGlasstualVersion"] as? String else {
				obsoleteBundles.append(bundle)

				NSLog(" ---------------------------- ERROR ---------------------------- ")
				NSLog("                                                                 ")
				NSLog("  Glasstual has failed to load the bundle at the following path    ")
				NSLog("  which did not specify a minimum version:                       ")
				NSLog("                                                                 ")
				NSLog("     Bundle Path: %@", bundle.bundlePath)
				NSLog("                                                                 ")
				NSLog("  Please add a key-value pair in the bundle's Info.plist file    ")
				NSLog("  with the key name as \"MinimumGlasstualVersion\"                 ")
				NSLog("                                                                 ")
				NSLog("  For example, to support this version and later:                ")
				NSLog("                                                                 ")
				NSLog("     <key>MinimumGlasstualVersion</key>                            ")
				NSLog("     <string>%@</string>", THOPluginProtocolCompatibilityMinimumVersion)
				NSLog("                                                                 ")
				NSLog(" --------------------------------------------------------------- ")

				continue
			}

			let comparisonResult = comparisonVersion.compare(
				THOPluginProtocolCompatibilityMinimumVersion,
				options: .numeric
			)

			if comparisonResult == .orderedAscending {
				obsoleteBundles.append(bundle)

				NSLog(" ---------------------------- ERROR ---------------------------- ")
				NSLog("                                                                 ")
				NSLog("  Glasstual has failed to load the bundle at the following path    ")
				NSLog("  because the specified minimum version is out of range:         ")
				NSLog("                                                                 ")
				NSLog("     Bundle Path: %@", bundle.bundlePath)
				NSLog("                                                                 ")
				NSLog("     Minimum version specified by bundle: %@", comparisonVersion)
				NSLog(
					"     Version used by Glasstual for comparison: %@",
					THOPluginProtocolCompatibilityMinimumVersion
				)
				NSLog("                                                                 ")
				NSLog(" --------------------------------------------------------------- ")

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

		let mutableLoaded = NSMutableArray(array: loadedPlugins)

		XRPerformBlockAsynchronouslyOnMainQueue { [weak self] in
			self?.promptForPendingApprovals(pendingApprovals, at: 0, loadedPlugins: mutableLoaded)
		}
	}

	private func loadBundleAsPlugin(_ bundle: Bundle) -> PluginItem? {
		let plugin = PluginItem()

		guard plugin.loadBundle(bundle) else {
			return nil
		}

		updateSupportedFeaturesProperty(with: plugin)

		return plugin
	}

	private func finishLoading(with loadedPlugins: [PluginItem]) {
		self.loadedPlugins = loadedPlugins
		pluginsLoaded = true

		XRPerformBlockAsynchronouslyOnMainQueue { [weak self] in
			guard let self else {
				return
			}

			checkForRejectedBundles()
			checkForObsoleteBundles()

			NotificationCenter.default.post(
				name: Notification.Name("THOPluginManagerFinishedLoadingPluginsNotification"),
				object: self
			)
		}
	}

	private func unloadPluginsInternal() {
		for plugin in loadedPlugins ?? [] {
			plugin.unloadBundle()
		}

		loadedPlugins = nil
	}

	// MARK: - Signature Validation

	private func isBundledExtension(_ bundle: Bundle) -> Bool {
		let applicationPath = (Bundle.main.bundlePath as NSString).standardizingPath
		let bundlePath = (bundle.bundlePath as NSString).standardizingPath

		return bundlePath.hasPrefix(applicationPath + "/")
	}

	private nonisolated(unsafe) static let applicationTeamIdentifier: String? = {
		var code: SecCode?
		guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code else {
			return nil
		}

		var signingInformation: CFDictionary?
		let status = SecCodeCopySigningInformation(
			code as! SecStaticCode,
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

		if status != errSecSuccess || signingInformation == nil {
			error?.pointee = Self.error(withStatus: status)
			return false
		}

		let information = signingInformation as! NSDictionary
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

	// MARK: - Approvals

	private static var approvals: [String: [String: Any]] {
		TPCPreferencesUserDefaults.shared().dictionary(forKey: approvalsDefaultsKey)
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

		TPCPreferencesUserDefaults.shared().set(approvals, forKey: Self.approvalsDefaultsKey)
	}

	@objc
	public class func resetApprovals() {
		TPCPreferencesUserDefaults.shared().removeObject(forKey: approvalsDefaultsKey)
	}

	private func promptForPendingApprovals(
		_ pendingApprovals: [PluginPendingApproval],
		at index: Int,
		loadedPlugins: NSMutableArray
	) {
		if index >= pendingApprovals.count {
			let plugins = loadedPlugins.compactMap { $0 as? PluginItem }

			XRPerformBlockAsynchronouslyOnQueue(PluginDispatcher.dispatchQueue()) { [weak self] in
				self?.finishLoading(with: plugins)
			}

			return
		}

		let pending = pendingApprovals[index]
		let bundle = pending.bundle
		let bundleIdentifier = bundle.bundleIdentifier ?? ""
		let teamIdentifier = pending.teamIdentifier

		var displayName = bundle.displayName ?? ""
		if displayName.isEmpty {
			displayName = (bundle.bundlePath as NSString).lastPathComponent
		}

		let tildePath = (bundle.bundleURL as NSURL).standardizedTildePath ?? bundle.bundlePath
		guard let window = NSObject.masterController().mainWindow else {
			return
		}

		TDCAlert.alertSheet(
			with: window,
			body: LocalizedKey(
				"Prompts[b4n-8z]",
				displayName,
				bundleIdentifier,
				teamIdentifier,
				tildePath
			),
			title: LocalizedKey("Prompts[pq7-2k]", displayName),
			defaultButton: LocalizedKey("Prompts[r9x-3m]"),
			alternateButton: LocalizedKey("Prompts[w2d-5h]"),
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

			XRPerformBlockAsynchronouslyOnQueue(PluginDispatcher.dispatchQueue()) {
				if approved {
					if let plugin = self.loadBundleAsPlugin(bundle) {
						loadedPlugins.add(plugin)
					}
				} else {
					Self.logger.info(
						"Not loading the bundle at “\(bundle.bundlePath, privacy: .public)“ because the user declined it"
					)
				}

				XRPerformBlockAsynchronouslyOnMainQueue {
					self.promptForPendingApprovals(
						pendingApprovals,
						at: index + 1,
						loadedPlugins: loadedPlugins
					)
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
			withMessage: LocalizedKey("Prompts[t8y-4p]"),
			title: LocalizedKey("Prompts[j6c-1v]", bundlesName),
			defaultButton: LocalizedKey("Prompts[u5k-9n]"),
			alternateButton: nil
		)
	}

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
				   fileExtension != TPCResourceManagerScriptDocumentTypeExtensionWithoutPeriod
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
		TPCResourceManager.array(fromResources: "StaticStore", key: "THOPluginManager List of Forbidden Commands")
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
		let bundlesName = Bundle.formattedDisplayNames(for: thirdPartyBundles)

		_ = TDCAlert.alert(
			withMessage: LocalizedKey(
				"Prompts[45a-df]",
				THOPluginProtocolCompatibilityMinimumVersion
			),
			title: LocalizedKey("Prompts[af6-45]", bundlesName),
			defaultButton: LocalizedKey("Prompts[324-5d]"),
			alternateButton: nil,
			otherButton: LocalizedKey("Prompts[0ik-o9]"),
			suppressionKey: nil,
			suppressionText: nil
		) { [weak self] buttonClicked, _, _ in
			guard buttonClicked == .other else {
				return
			}

			Bundle.openInstallationLocations(for: thirdPartyBundles)
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

	// MARK: - Extension Information

	private func updateSupportedFeaturesProperty(with plugin: PluginItem) {
		let features: [THOPluginItemSupportedFeature] = [
			.didReceiveCommandEvent,
			.didReceivePlainTextMessageEvent,
			.newMessagePostedEvent,
			.outputSuppressionRules,
			.preferencePane,
			.serverInputDataInterception,
			.subscribedServerInputCommands,
			.subscribedUserInputCommands,
			.userInputDataInterception,
			.webViewJavaScriptPayloads,
			.willRenderMessageEvent,
		]

		for feature in features {
			if plugin.supportsFeature(feature), supportsFeature(feature) == false {
				supportedFeatures.insert(feature)
			}
		}
	}

	@objc(supportsFeature:)
	public func supportsFeature(_ feature: THOPluginItemSupportedFeature) -> Bool {
		supportedFeatures.contains(feature)
	}

	@objc public var pluginOutputSuppressionRules: [THOPluginOutputSuppressionRule] {
		guard pluginsLoaded else {
			return []
		}

		if let cachedOutputSuppressionRules {
			return cachedOutputSuppressionRules
		}

		var allRules: [THOPluginOutputSuppressionRule] = []

		for plugin in loadedPlugins ?? [] {
			guard plugin.supportsFeature(.outputSuppressionRules),
			      let rules = plugin.outputSuppressionRules
			else {
				continue
			}

			allRules.append(contentsOf: rules)
		}

		cachedOutputSuppressionRules = allRules
		return allRules
	}

	@objc public var supportedUserInputCommands: [String] {
		guard pluginsLoaded else {
			return []
		}

		if let cachedUserInputCommands {
			return cachedUserInputCommands
		}

		var allCommands: [String] = []

		for plugin in loadedPlugins ?? [] {
			guard plugin.supportsFeature(.subscribedUserInputCommands),
			      let commands = plugin.supportedUserInputCommands
			else {
				continue
			}

			for command in commands where allCommands.contains(command) == false {
				allCommands.append(command)
			}
		}

		allCommands.sort()
		cachedUserInputCommands = allCommands
		return allCommands
	}

	@objc public var supportedServerInputCommands: [String] {
		guard pluginsLoaded else {
			return []
		}

		if let cachedServerInputCommands {
			return cachedServerInputCommands
		}

		var allCommands: [String] = []

		for plugin in loadedPlugins ?? [] {
			guard plugin.supportsFeature(.subscribedServerInputCommands),
			      let commands = plugin.supportedServerInputCommands
			else {
				continue
			}

			for command in commands where allCommands.contains(command) == false {
				allCommands.append(command)
			}
		}

		allCommands.sort()
		cachedServerInputCommands = allCommands
		return allCommands
	}

	@objc public var pluginsWithPreferencePanes: [PluginItem] {
		guard pluginsLoaded else {
			return []
		}

		if let cachedPluginsWithPreferencePanes {
			return cachedPluginsWithPreferencePanes
		}

		var allExtensions: [PluginItem] = []

		for plugin in loadedPlugins ?? [] {
			guard plugin.supportsFeature(.preferencePane) else {
				continue
			}

			allExtensions.append(plugin)
		}

		allExtensions.sort {
			($0.pluginPreferencesPaneMenuItemTitle ?? "")
				.compare($1.pluginPreferencesPaneMenuItemTitle ?? "") == .orderedAscending
		}

		cachedPluginsWithPreferencePanes = allExtensions
		return allExtensions
	}
}
