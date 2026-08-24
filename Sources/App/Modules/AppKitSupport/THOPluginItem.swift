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

@objc(THOPluginItem)
public final class PluginItem: NSObject {
	@objc public private(set) var bundle: Bundle?
	@objc public private(set) var primaryClass: AnyObject?
	@objc public private(set) var supportedFeatures: THOPluginItemSupportedFeature = []
	@objc public private(set) var supportedUserInputCommands: [String]?
	@objc public private(set) var supportedServerInputCommands: [String]?
	@objc public private(set) var outputSuppressionRules: [THOPluginOutputSuppressionRule]?
	@objc public private(set) var pluginPreferencesPaneMenuItemTitle: String?
	@objc public private(set) var pluginPreferencesPaneView: NSView?

	@objc(loadBundle:)
	@discardableResult
	public func loadBundle(_ bundle: Bundle) -> Bool {
		guard let principalClassType = bundle.principalClass as? NSObject.Type else {
			return false
		}

		/* Initialize the principal class */
		let primaryClass = principalClassType.init() as AnyObject

		/* -loadBundle: is invoked on the plugin dispatch queue. Plugins
		 expect lifecycle and view related calls on the main thread. */
		if primaryClass.responds(to: Selector(("pluginLoadedIntoMemory"))) {
			XRPerformBlockSynchronouslyOnMainQueue {
				_ = primaryClass.perform(Selector(("pluginLoadedIntoMemory")))
			}
		}

		/* Build list of supported features */
		var supportedFeatures: THOPluginItemSupportedFeature = []

		/* Process server output suppression rules */
		if primaryClass.responds(to: Selector(("pluginOutputSuppressionRules"))) {
			let outputRules = primaryClass.value(forKey: "pluginOutputSuppressionRules")

			if let outputRules = outputRules as? [Any], outputRules.isEmpty == false {
				var sharedRules: [THOPluginOutputSuppressionRule] = []

				for outputRule in outputRules {
					guard let rule = outputRule as? THOPluginOutputSuppressionRule else {
						continue
					}

					sharedRules.append(rule)
				}

				self.outputSuppressionRules = sharedRules
				supportedFeatures.insert(.outputSuppressionRules)
			}
		}

		/* Does the bundle have a preference pane?... */
		if primaryClass.responds(to: Selector(("pluginPreferencesPaneMenuItemName"))),
			primaryClass.responds(to: Selector(("pluginPreferencesPaneView")))
		{
			let itemTitle = primaryClass.value(forKey: "pluginPreferencesPaneMenuItemName") as? String

			var itemView: AnyObject?

			XRPerformBlockSynchronouslyOnMainQueue {
				itemView = primaryClass.value(forKey: "pluginPreferencesPaneView") as AnyObject?
			}

			if let itemTitle, itemTitle.isEmpty == false, let itemView = itemView as? NSView {
				pluginPreferencesPaneMenuItemTitle = itemTitle
				pluginPreferencesPaneView = itemView
				supportedFeatures.insert(.preferencePane)
			}
		}

		/* Process user input commands */
		if primaryClass.responds(to: Selector(("subscribedUserInputCommands"))),
			primaryClass.responds(
				to: Selector(("userInputCommandInvokedOnClient:commandString:messageString:"))
			)
		{
			let subscribedCommands = primaryClass.value(forKey: "subscribedUserInputCommands")

			if let subscribedCommands = subscribedCommands as? [Any], subscribedCommands.isEmpty == false {
				var supportedCommands: [String] = []

				for command in subscribedCommands {
					guard let command = command as? String, command.isEmpty == false else {
						continue
					}

					supportedCommands.append(command.lowercased())
				}

				supportedUserInputCommands = supportedCommands
				supportedFeatures.insert(.subscribedUserInputCommands)
			}
		}

		/* Process server input commands */
		if primaryClass.responds(to: Selector(("subscribedServerInputCommands"))),
			primaryClass.responds(to: Selector(("didReceiveServerInput:onClient:")))
		{
			let subscribedCommands = primaryClass.value(forKey: "subscribedServerInputCommands")

			if let subscribedCommands = subscribedCommands as? [Any], subscribedCommands.isEmpty == false {
				var supportedCommands: [String] = []

				for command in subscribedCommands {
					guard let command = command as? String, command.isEmpty == false else {
						continue
					}

					supportedCommands.append(command.lowercased())
				}

				supportedServerInputCommands = supportedCommands
				supportedFeatures.insert(.subscribedServerInputCommands)
			}
		}

		/* Check whether plugin supports certain events so we do not have
		 to ask if it responds to the selector every time we call it. */

		/* Renderer events */
		if primaryClass.responds(to: Selector(("didPostNewMessage:forViewController:"))) {
			supportedFeatures.insert(.newMessagePostedEvent)
		}

		if primaryClass.responds(
			to: Selector(("willRenderMessage:forViewController:lineType:memberType:"))
		) {
			supportedFeatures.insert(.willRenderMessageEvent)
		}

		if primaryClass.responds(to: Selector(("didReceiveJavaScriptPayload:fromViewController:"))) {
			supportedFeatures.insert(.webViewJavaScriptPayloads)
		}

		/* Data interception */
		if primaryClass.responds(to: Selector(("interceptServerInput:for:"))) {
			supportedFeatures.insert(.serverInputDataInterception)
		}

		if primaryClass.responds(to: Selector(("interceptUserInput:command:"))) {
			supportedFeatures.insert(.userInputDataInterception)
		}

		if primaryClass.responds(
			to: Selector(
				("receivedText:authoredBy:destinedFor:asLineType:onClient:receivedAt:wasEncrypted:")
			)
		) {
			supportedFeatures.insert(.didReceivePlainTextMessageEvent)
		}

		if primaryClass.responds(
			to: Selector(
				("receivedCommand:withText:authoredBy:destinedFor:onClient:receivedAt:referenceMessage:")
			)
		) {
			supportedFeatures.insert(.didReceiveCommandEvent)
		}

		/* Finish up */
		self.bundle = bundle
		self.supportedFeatures = supportedFeatures
		self.primaryClass = primaryClass

		return true
	}

	@objc
	public func unloadBundle() {
		guard let primaryClass else {
			return
		}

		if primaryClass.responds(to: Selector(("pluginWillBeUnloadedFromMemory"))) {
			XRPerformBlockSynchronouslyOnMainQueue {
				_ = primaryClass.perform(Selector(("pluginWillBeUnloadedFromMemory")))
			}
		}

		self.primaryClass = nil
		bundle = nil
	}

	@objc(supportsFeature:)
	public func supportsFeature(_ feature: THOPluginItemSupportedFeature) -> Bool {
		supportedFeatures.contains(feature)
	}
}
