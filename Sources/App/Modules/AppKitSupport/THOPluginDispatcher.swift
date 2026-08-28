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

import CocoaExtensions
import Foundation
import GlasstualPluginKit

@objc(THOPluginDispatcher)
public final nonisolated class PluginDispatcher: NSObject {
	private nonisolated(unsafe) static let didPostNewMessageObjectCache =
		NSCache<NSString, THOPluginDidPostNewMessageConcreteObject>()

	private static let _dispatchQueue = DispatchQueue(
		label: "Glasstual.THOPluginDispatcher.PluginManagerDispatchQueue",
		qos: .default
	)

	@objc
	public static func dispatchQueue() -> DispatchQueue {
		_dispatchQueue
	}

	private static var plugins: [PluginItem] {
		SharedApplication.sharedPluginManager().loadedPlugins ?? []
	}

	@MainActor
	public static func dispatchReceivedCommand(
		_ command: String,
		withText text: String?,
		authoredBy textAuthor: Prefix,
		destinedFor textDestination: IRCChannel?,
		onClient client: IRCClient,
		receivedAt: Date,
		referenceMessage: Message?
	) -> Bool {
		for plugin in plugins {
			guard plugin.supportsFeature(.didReceiveCommandEvent),
			      let handler = plugin.primaryClass as? any PluginIncomingCommandHandling
			else {
				continue
			}

			let shouldContinue = handler.receivedCommand(
				PluginIncomingCommandEvent(
					command: command,
					text: text,
					author: PluginHostAdapter.makeSender(textAuthor),
					destination: textDestination.map(PluginHostAdapter.makeChannel),
					client: PluginHostAdapter.makeClient(client),
					receivedAt: receivedAt,
					messageParameters: referenceMessage?.params ?? []
				)
			)

			if shouldContinue == false {
				return false
			}
		}

		return true
	}

	@MainActor
	public static func dispatchReceivedText(
		_ text: String,
		authoredBy textAuthor: Prefix,
		destinedFor textDestination: IRCChannel?,
		as lineType: TVCLogLineType,
		onClient client: IRCClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		for plugin in plugins {
			guard plugin.supportsFeature(.didReceivePlainTextMessageEvent),
			      let primaryClass = plugin.primaryClass
			else {
				continue
			}

			guard let handler = primaryClass as? any PluginTextEventHandling else {
				continue
			}
			let returnedValue = handler.receivedText(
				PluginTextEvent(
					text: text,
					author: PluginHostAdapter.makeSender(textAuthor),
					destination: textDestination.map(PluginHostAdapter.makeChannel),
					kind: PluginHostAdapter.messageKind(for: lineType),
					client: PluginHostAdapter.makeClient(client),
					receivedAt: receivedAt,
					wasEncrypted: wasEncrypted
				)
			)

			if returnedValue == false {
				return false
			}
		}

		return true
	}

	@objc(interceptServerInput:for:)
	@MainActor
	public static func interceptServerInput(_ inputObject: Message, for client: IRCClient) -> Message? {
		var returnValue: Message = inputObject

		for plugin in plugins {
			guard plugin.supportsFeature(.serverInputDataInterception),
			      let primaryClass = plugin.primaryClass
			else {
				continue
			}

			guard let interceptor = primaryClass as? any PluginServerMessageIntercepting else {
				continue
			}
			guard let intercepted = interceptor.interceptServerInput(
				PluginHostAdapter.makeServerMessage(returnValue),
				client: PluginHostAdapter.makeClient(client)
			) else {
				return nil
			}
			returnValue = PluginHostAdapter.applying(intercepted, to: returnValue)
		}

		return returnValue
	}

	@objc(interceptUserInput:command:)
	@MainActor
	public static func interceptUserInput(_ inputObject: Any, command commandString: IRCRemoteCommand) -> Any? {
		var returnValue: Any = inputObject

		for plugin in plugins {
			guard plugin.supportsFeature(.userInputDataInterception),
			      let interceptor = plugin.primaryClass as? any PluginUserInputIntercepting
			else {
				continue
			}

			guard let returnedValue = interceptor.interceptUserInput(
				PluginUserInput(value: returnValue, commandRawValue: commandString.rawValue)
			) else {
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
	public static func willRenderMessage(
		_ newMessage: String,
		forViewController _: LogController,
		lineType: TVCLogLineType,
		memberType _: TVCLogLineMemberType
	) -> String {
		var returnValue = newMessage

		for plugin in plugins {
			guard plugin.supportsFeature(.willRenderMessageEvent),
			      let renderer = plugin.primaryClass as? any PluginMessageRendering
			else {
				continue
			}

			guard let returnedValue = renderer.willRenderMessage(
				PluginRenderEvent(message: returnValue, kind: PluginHostAdapter.messageKind(for: lineType))
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
	public static func userInputCommandInvoked(
		onClient client: IRCClient,
		commandString: String,
		messageString: String
	) {
		let client = PluginHostAdapter.makeClient(client)
		let host = PluginHostAdapter.makeContext()
		performAsynchronously(on: dispatchQueue()) {
			let lowercaseCommand = commandString.lowercased()
			let uppercaseCommand = commandString.uppercased()

			for plugin in self.plugins {
				guard plugin.supportsFeature(.subscribedUserInputCommands),
				      plugin.supportedUserInputCommands?.contains(lowercaseCommand) == true,
				      let primaryClass = plugin.primaryClass
				else {
					continue
				}

				guard let handler = primaryClass as? any PluginCommandHandling else { continue }
				handler.userInputCommandInvoked(
					PluginCommandInvocation(
						client: client,
						command: uppercaseCommand,
						message: messageString,
						selectedChannel: host.selectedChannel,
						connectedClients: host.clients
					)
				)
			}
		}
	}

	public static func didReceiveJavaScriptPayload(
		_ payloadObject: THOPluginWebViewJavaScriptPayloadConcreteObject,
		fromViewController _: LogController
	) {
		performAsynchronously(on: dispatchQueue()) {
			for plugin in self.plugins {
				guard plugin.supportsFeature(.webViewJavaScriptPayloads),
				      let handler = plugin.primaryClass as? any PluginJavaScriptPayloadHandling
				else {
					continue
				}

				handler.didReceiveJavaScriptPayload(payloadObject)
			}
		}
	}

	@objc(didReceiveServerInput:onClient:)
	public static func didReceiveServerInput(_ inputObject: Message, onClient client: IRCClient) {
		let client = PluginHostAdapter.makeClient(client)
		performAsynchronously(on: dispatchQueue()) {
			let messageObject = inputObject.didReceiveServerInputConcreteObject()

			messageObject.networkAddress = client.serverAddress
			messageObject.networkName = client.networkName

			let lowercaseCommand = inputObject.command.lowercased()

			for plugin in self.plugins {
				guard plugin.supportsFeature(.subscribedServerInputCommands),
				      plugin.supportedServerInputCommands?.contains(lowercaseCommand) == true,
				      let primaryClass = plugin.primaryClass
				else {
					continue
				}

				guard let handler = primaryClass as? any PluginServerInputHandling else { continue }
				handler.didReceiveServerInput(messageObject, client: client)
			}
		}
	}

	public static func enqueueDidPostNewMessage(_ messageObject: THOPluginDidPostNewMessageConcreteObject) {
		didPostNewMessageObjectCache.setObject(messageObject, forKey: messageObject.lineNumber as NSString)
	}

	@objc(dequeueDidPostNewMessageWithLineNumber:forViewController:)
	public static func dequeueDidPostNewMessage(
		withLineNumber messageLineNumber: String,
		forViewController _: LogController
	) {
		guard let messageObject = didPostNewMessageObjectCache.object(forKey: messageLineNumber as NSString)
		else {
			return
		}

		performAsynchronously(on: dispatchQueue()) {
			for plugin in self.plugins {
				guard plugin.supportsFeature(.newMessagePostedEvent),
				      let handler = plugin.primaryClass as? any PluginPostedMessageHandling
				else {
					continue
				}

				handler.didPostNewMessage(messageObject)
			}
		}
	}
}
