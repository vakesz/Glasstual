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

import Foundation

private func legacyLogController(_ controller: LogController) -> TVCLogController {
	unsafeBitCast(controller, to: TVCLogController.self)
}

@objc(THOPluginDispatcher)
public final class PluginDispatcher: NSObject {
	private nonisolated(unsafe) static let didPostNewMessageObjectCache =
		NSCache<NSString, THOPluginDidPostNewMessageConcreteObject>()

	private static let _dispatchQueue = DispatchQueue(
		label: "Glasstual.THOPluginDispatcher.PluginManagerDispatchQueue",
		qos: .default
	)

	@objc
	public class func dispatchQueue() -> DispatchQueue {
		_dispatchQueue
	}

	private class var plugins: [PluginItem] {
		TXSharedApplication.sharedPluginManager().loadedPlugins as? [PluginItem] ?? []
	}

	@objc(receivedCommand:withText:authoredBy:destinedFor:onClient:receivedAt:referenceMessage:)
	public class func dispatchReceivedCommand(
		_ command: String,
		withText text: String?,
		authoredBy textAuthor: IRCPrefix,
		destinedFor textDestination: IRCChannel?,
		onClient client: IRCClient,
		receivedAt: Date,
		referenceMessage: Message?
	) -> Bool {
		let selector = NSSelectorFromString(
			"receivedCommand:withText:authoredBy:destinedFor:onClient:receivedAt:referenceMessage:"
		)

		typealias MethodType = @convention(c) (
			AnyObject, Selector, NSString, NSString?, IRCPrefix, IRCChannel?, IRCClient, NSDate, Message?
		) -> Bool

		for plugin in plugins {
			guard plugin.supportsFeature(.didReceiveCommandEvent),
			      let primaryClass = plugin.primaryClass as? NSObject,
			      primaryClass.responds(to: selector),
			      let method = class_getInstanceMethod(type(of: primaryClass), selector)
			else {
				continue
			}

			let impl = unsafeBitCast(method_getImplementation(method), to: MethodType.self)
			let ok = impl(
				primaryClass,
				selector,
				command as NSString,
				text as NSString?,
				textAuthor,
				textDestination,
				client,
				receivedAt as NSDate,
				referenceMessage
			)

			if ok == false {
				return false
			}
		}

		return true
	}

	@objc(receivedText:authoredBy:destinedFor:asLineType:onClient:receivedAt:wasEncrypted:)
	public class func dispatchReceivedText(
		_ text: String,
		authoredBy textAuthor: IRCPrefix,
		destinedFor textDestination: IRCChannel?,
		as lineType: TVCLogLineType,
		onClient client: IRCClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		for plugin in plugins {
			guard plugin.supportsFeature(.didReceivePlainTextMessageEvent),
			      let primaryClass = plugin.primaryClass as? THOPluginProtocol
			else {
				continue
			}

			let returnedValue =
				primaryClass.receivedText?(
					text,
					authoredBy: textAuthor,
					destinedFor: textDestination,
					as: lineType,
					on: client,
					receivedAt: receivedAt,
					wasEncrypted: wasEncrypted
				) ?? true

			if returnedValue == false {
				return false
			}
		}

		return true
	}

	@objc(interceptServerInput:for:)
	public class func interceptServerInput(_ inputObject: Message, for client: IRCClient) -> Message? {
		var returnValue: Message = inputObject

		for plugin in plugins {
			guard plugin.supportsFeature(.serverInputDataInterception),
			      let primaryClass = plugin.primaryClass as? THOPluginProtocol
			else {
				continue
			}

			guard let returnedValue = primaryClass.interceptServerInput?(returnValue, for: client) else {
				return nil
			}

			if returnedValue !== returnValue {
				if returnedValue is MessageMutable {
					returnValue = returnedValue.copy() as! Message
				} else {
					returnValue = returnedValue
				}
			}
		}

		return returnValue
	}

	@objc(interceptUserInput:command:)
	public class func interceptUserInput(_ inputObject: Any, command commandString: IRCRemoteCommand) -> Any? {
		var returnValue: Any = inputObject

		for plugin in plugins {
			guard plugin.supportsFeature(.userInputDataInterception),
			      let primaryClass = plugin.primaryClass as? THOPluginProtocol
			else {
				continue
			}

			guard let returnedValue = primaryClass.interceptUserInput?(returnValue, command: commandString)
			else {
				return nil
			}

			let equal: Bool = {
				if let left = returnValue as? NSObject, let right = returnedValue as? NSObject {
					return left.isEqual(right)
				}

				return false
			}()

			if equal == false,
			   returnedValue is String || returnedValue is NSAttributedString
			{
				if returnedValue is NSMutableString || returnedValue is NSMutableAttributedString {
					returnValue = (returnedValue as AnyObject).copy()
				} else {
					returnValue = returnedValue
				}
			}
		}

		return returnValue
	}

	@objc(willRenderMessage:forViewController:lineType:memberType:)
	public class func willRenderMessage(
		_ newMessage: String,
		forViewController viewController: LogController,
		lineType: TVCLogLineType,
		memberType: TVCLogLineMemberType
	) -> String {
		var returnValue = newMessage

		for plugin in plugins {
			guard plugin.supportsFeature(.willRenderMessageEvent),
			      let primaryClass = plugin.primaryClass as? THOPluginProtocol
			else {
				continue
			}

			guard let returnedValue = primaryClass.willRenderMessage?(
				returnValue,
				forViewController: legacyLogController(viewController),
				lineType: lineType,
				memberType: memberType
			), returnedValue.isEmpty == false else {
				continue
			}

			if returnedValue == returnValue {
				continue
			}

			returnValue = returnedValue
		}

		return returnValue
	}

	@objc(userInputCommandInvokedOnClient:commandString:messageString:)
	public class func userInputCommandInvoked(
		onClient client: IRCClient,
		commandString: String,
		messageString: String
	) {
		XRPerformBlockAsynchronouslyOnQueue(dispatchQueue()) {
			let lowercaseCommand = commandString.lowercased()
			let uppercaseCommand = commandString.uppercased()

			for plugin in self.plugins {
				guard plugin.supportsFeature(.subscribedUserInputCommands),
				      plugin.supportedUserInputCommands?.contains(lowercaseCommand) == true,
				      let primaryClass = plugin.primaryClass as? THOPluginProtocol
				else {
					continue
				}

				primaryClass.userInputCommandInvoked?(
					on: client,
					command: uppercaseCommand,
					messageString: messageString
				)
			}
		}
	}

	@objc(didReceiveJavaScriptPayload:fromViewController:)
	public class func didReceiveJavaScriptPayload(
		_ payloadObject: THOPluginWebViewJavaScriptPayloadConcreteObject,
		fromViewController viewController: LogController
	) {
		XRPerformBlockAsynchronouslyOnQueue(dispatchQueue()) {
			for plugin in self.plugins {
				guard plugin.supportsFeature(.webViewJavaScriptPayloads),
				      let primaryClass = plugin.primaryClass as? THOPluginProtocol
				else {
					continue
				}

				primaryClass.didReceiveJavaScriptPayload?(
					payloadObject,
					fromViewController: legacyLogController(viewController)
				)
			}
		}
	}

	@objc(didReceiveServerInput:onClient:)
	public class func didReceiveServerInput(_ inputObject: Message, onClient client: IRCClient) {
		XRPerformBlockAsynchronouslyOnQueue(dispatchQueue()) {
			let messageObject = inputObject.didReceiveServerInputConcreteObject()

			messageObject.networkAddress = client.serverAddress
			messageObject.networkName = client.networkName

			let lowercaseCommand = inputObject.command.lowercased()

			for plugin in self.plugins {
				guard plugin.supportsFeature(.subscribedServerInputCommands),
				      plugin.supportedServerInputCommands?.contains(lowercaseCommand) == true,
				      let primaryClass = plugin.primaryClass as? THOPluginProtocol
				else {
					continue
				}

				primaryClass.didReceiveServerInput?(messageObject, on: client)
			}
		}
	}

	@objc(enqueueDidPostNewMessage:)
	public class func enqueueDidPostNewMessage(_ messageObject: THOPluginDidPostNewMessageConcreteObject) {
		didPostNewMessageObjectCache.setObject(messageObject, forKey: messageObject.lineNumber as NSString)
	}

	@objc(dequeueDidPostNewMessageWithLineNumber:forViewController:)
	public class func dequeueDidPostNewMessage(
		withLineNumber messageLineNumber: String,
		forViewController viewController: LogController
	) {
		guard let messageObject = didPostNewMessageObjectCache.object(forKey: messageLineNumber as NSString)
		else {
			return
		}

		XRPerformBlockAsynchronouslyOnQueue(dispatchQueue()) {
			for plugin in self.plugins {
				guard plugin.supportsFeature(.newMessagePostedEvent),
				      let primaryClass = plugin.primaryClass as? THOPluginProtocol
				else {
					continue
				}

				primaryClass.didPostNewMessage?(
					messageObject,
					forViewController: legacyLogController(viewController)
				)
			}
		}
	}
}
