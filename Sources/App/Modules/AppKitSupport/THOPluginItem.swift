/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import GlasstualPluginKit
import os

public nonisolated struct PluginSupportedFeature: OptionSet, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	public static let didReceiveCommandEvent = Self(rawValue: 1 << 1)
	public static let didReceivePlainTextMessageEvent = Self(rawValue: 1 << 2)
	public static let newMessagePostedEvent = Self(rawValue: 1 << 4)
	public static let outputSuppressionRules = Self(rawValue: 1 << 5)
	public static let preferencePane = Self(rawValue: 1 << 6)
	public static let serverInputDataInterception = Self(rawValue: 1 << 7)
	public static let subscribedServerInputCommands = Self(rawValue: 1 << 8)
	public static let subscribedUserInputCommands = Self(rawValue: 1 << 9)
	public static let userInputDataInterception = Self(rawValue: 1 << 10)
	public static let webViewJavaScriptPayloads = Self(rawValue: 1 << 11)
	public static let willRenderMessageEvent = Self(rawValue: 1 << 12)
}

/// One successfully loaded plugin bundle and everything the host learned about
/// it while loading.
///
/// The value is immutable: `load(_:host:)` is the only way to make one, and it
/// either returns a fully populated item or `nil`. Nothing observes a
/// half-configured plugin.
@objc(THOPluginItem)
public final nonisolated class PluginItem: NSObject {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PluginItem"
	)

	@objc public let bundle: Bundle
	@objc public let primaryClass: AnyObject
	public let supportedFeatures: PluginSupportedFeature
	@objc public let supportedUserInputCommands: [String]
	@objc public let supportedServerInputCommands: [String]
	public let outputSuppressionRules: [PluginOutputSuppressionRule]
	@objc public let pluginPreferencesPaneMenuItemTitle: String?
	@objc public let pluginPreferencesPaneView: NSView?

	private init(
		bundle: Bundle,
		primaryClass: AnyObject,
		supportedFeatures: PluginSupportedFeature,
		supportedUserInputCommands: [String],
		supportedServerInputCommands: [String],
		outputSuppressionRules: [PluginOutputSuppressionRule],
		pluginPreferencesPaneMenuItemTitle: String?,
		pluginPreferencesPaneView: NSView?
	) {
		self.bundle = bundle
		self.primaryClass = primaryClass
		self.supportedFeatures = supportedFeatures
		self.supportedUserInputCommands = supportedUserInputCommands
		self.supportedServerInputCommands = supportedServerInputCommands
		self.outputSuppressionRules = outputSuppressionRules
		self.pluginPreferencesPaneMenuItemTitle = pluginPreferencesPaneMenuItemTitle
		self.pluginPreferencesPaneView = pluginPreferencesPaneView
	}

	/// Instantiates `bundle`'s principal class and runs its load callback.
	/// Returns `nil`, having logged why, when the bundle is not a plugin.
	@MainActor
	public static func load(_ bundle: Bundle, host: PluginHostContext) -> PluginItem? {
		guard let principalClassType = bundle.principalClass as? NSObject.Type else {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its principal class is missing or is not an Objective-C class"
			)
			return nil
		}

		guard let plugin = principalClassType.init() as? any GlasstualPlugin else {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its principal class does not conform to GlasstualPlugin"
			)
			return nil
		}

		plugin.pluginLoaded(using: host)

		var features = detectedFeatures(of: plugin)

		let suppressionRules = (plugin as? any PluginOutputSuppressionProviding)?
			.pluginOutputSuppressionRules ?? []
		if suppressionRules.isEmpty == false {
			features.insert(.outputSuppressionRules)
		}

		let preferencePane = preferencePane(of: plugin, in: bundle)
		if preferencePane != nil {
			features.insert(.preferencePane)
		}

		let userInputCommands = normalizedCommands(
			(plugin as? any PluginCommandHandling)?.subscribedUserInputCommands ?? []
		)
		if userInputCommands.isEmpty == false {
			features.insert(.subscribedUserInputCommands)
		}

		let serverInputCommands = normalizedCommands(
			(plugin as? any PluginServerInputHandling)?.subscribedServerInputCommands ?? []
		)
		if serverInputCommands.isEmpty == false {
			features.insert(.subscribedServerInputCommands)
		}

		return PluginItem(
			bundle: bundle,
			primaryClass: plugin,
			supportedFeatures: features,
			supportedUserInputCommands: userInputCommands,
			supportedServerInputCommands: serverInputCommands,
			outputSuppressionRules: suppressionRules,
			pluginPreferencesPaneMenuItemTitle: preferencePane?.title,
			pluginPreferencesPaneView: preferencePane?.view
		)
	}

	@MainActor
	@objc
	public func unloadBundle() {
		(primaryClass as? any GlasstualPlugin)?.pluginWillUnload()
	}

	public func supportsFeature(_ feature: PluginSupportedFeature) -> Bool {
		supportedFeatures.contains(feature)
	}

	@MainActor
	private static func preferencePane(
		of plugin: any GlasstualPlugin,
		in bundle: Bundle
	) -> (title: String, view: NSView)? {
		guard let provider = plugin as? any PluginPreferencesProviding,
		      provider.pluginPreferencesPaneMenuItemName.isEmpty == false
		else {
			return nil
		}

		guard let view = provider.pluginPreferencesPaneView else {
			logger.error(
				"The plugin at “\(bundle.bundlePath, privacy: .public)“ names a preferences pane but supplied no view; its interface file most likely failed to load"
			)
			return nil
		}

		return (provider.pluginPreferencesPaneMenuItemName, view)
	}

	private static func normalizedCommands(_ commands: [String]) -> [String] {
		commands.filter { $0.isEmpty == false }.map { $0.lowercased() }
	}

	@MainActor
	private static func detectedFeatures(of plugin: any GlasstualPlugin) -> PluginSupportedFeature {
		var features: PluginSupportedFeature = []
		if plugin is any PluginPostedMessageHandling {
			features.insert(.newMessagePostedEvent)
		}
		if plugin is any PluginMessageRendering {
			features.insert(.willRenderMessageEvent)
		}
		if plugin is any PluginJavaScriptPayloadHandling {
			features.insert(.webViewJavaScriptPayloads)
		}
		if plugin is any PluginServerMessageIntercepting {
			features.insert(.serverInputDataInterception)
		}
		if plugin is any PluginUserInputIntercepting {
			features.insert(.userInputDataInterception)
		}
		if plugin is any PluginTextEventHandling {
			features.insert(.didReceivePlainTextMessageEvent)
		}
		if plugin is any PluginIncomingCommandHandling {
			features.insert(.didReceiveCommandEvent)
		}
		return features
	}
}
