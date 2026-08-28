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

@objc(THOPluginItem)
public final nonisolated class PluginItem: NSObject, @unchecked Sendable {
	@objc public private(set) var bundle: Bundle?
	@objc public private(set) var primaryClass: AnyObject?
	public private(set) var supportedFeatures: PluginSupportedFeature = []
	@objc public private(set) var supportedUserInputCommands: [String]?
	@objc public private(set) var supportedServerInputCommands: [String]?
	public private(set) var outputSuppressionRules: [PluginOutputSuppressionRule]?
	@objc public private(set) var pluginPreferencesPaneMenuItemTitle: String?
	@objc public private(set) var pluginPreferencesPaneView: NSView?

	@MainActor
	@discardableResult
	public func loadBundle(_ bundle: Bundle, host: PluginHostContext) -> Bool {
		guard let principalClassType = bundle.principalClass as? NSObject.Type else {
			return false
		}

		let primaryClass = principalClassType.init()
		guard let plugin = primaryClass as? any GlasstualPlugin else {
			return false
		}
		plugin.pluginLoaded(using: host)

		var supportedFeatures = detectedFeatures(of: plugin)

		if configureOutputSuppressionRules(from: plugin) {
			supportedFeatures.insert(.outputSuppressionRules)
		}

		if configurePreferencePane(from: plugin) {
			supportedFeatures.insert(.preferencePane)
		}

		if let commandPlugin = plugin as? any PluginCommandHandling {
			let commands = normalizedCommands(commandPlugin.subscribedUserInputCommands)
			supportedUserInputCommands = commands
			if commands.isEmpty == false {
				supportedFeatures.insert(.subscribedUserInputCommands)
			}
		}

		if let inputPlugin = plugin as? any PluginServerInputHandling {
			let commands = normalizedCommands(inputPlugin.subscribedServerInputCommands)
			supportedServerInputCommands = commands
			if commands.isEmpty == false {
				supportedFeatures.insert(.subscribedServerInputCommands)
			}
		}

		self.bundle = bundle
		self.supportedFeatures = supportedFeatures
		self.primaryClass = primaryClass

		return true
	}

	@MainActor
	@objc
	public func unloadBundle() {
		guard let primaryClass else {
			return
		}

		(primaryClass as? any GlasstualPlugin)?.pluginWillUnload()

		self.primaryClass = nil
		bundle = nil
	}

	public func supportsFeature(_ feature: PluginSupportedFeature) -> Bool {
		supportedFeatures.contains(feature)
	}

	private func configureOutputSuppressionRules(from plugin: any GlasstualPlugin) -> Bool {
		guard let provider = plugin as? any PluginOutputSuppressionProviding,
		      provider.pluginOutputSuppressionRules.isEmpty == false
		else {
			return false
		}

		outputSuppressionRules = provider.pluginOutputSuppressionRules
		return true
	}

	@MainActor
	private func configurePreferencePane(from plugin: any GlasstualPlugin) -> Bool {
		guard let provider = plugin as? any PluginPreferencesProviding,
		      provider.pluginPreferencesPaneMenuItemName.isEmpty == false
		else {
			return false
		}

		let itemView = provider.pluginPreferencesPaneView

		pluginPreferencesPaneMenuItemTitle = provider.pluginPreferencesPaneMenuItemName
		pluginPreferencesPaneView = itemView
		return true
	}

	private func normalizedCommands(_ commands: [String]) -> [String] {
		commands.filter { $0.isEmpty == false }.map { $0.lowercased() }
	}

	private func detectedFeatures(of plugin: any GlasstualPlugin) -> PluginSupportedFeature {
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
