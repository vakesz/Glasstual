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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

private struct OutboundTextCommand {
	let wireCommand: String
	let lineType: TVCLogLineType

	init?(_ command: IRCRemoteCommand) {
		switch command {
		case .privmsg:
			wireCommand = "PRIVMSG"
			lineType = .privateMessage
		case .privmsgAction:
			wireCommand = "PRIVMSG"
			lineType = .action
		case .notice:
			wireCommand = "NOTICE"
			lineType = .notice
		default:
			return nil
		}
	}
}

struct OutboundMessageCommandPolicy {
	let remoteCommand: IRCRemoteCommand
	let isOperatorMessage: Bool
	let isSecretMessage: Bool

	init?(command: String, silentlyConnecting: Bool) {
		switch command {
		case "msg", "omsg", "smsg", "umsg":
			remoteCommand = .privmsg
			isOperatorMessage = command == "omsg"
			isSecretMessage = command == "smsg" || silentlyConnecting
		case "me", "sme", "ume":
			remoteCommand = .privmsgAction
			isOperatorMessage = false
			isSecretMessage = command == "sme"
		case "notice", "onotice", "unotice":
			remoteCommand = .notice
			isOperatorMessage = command == "onotice"
			isSecretMessage = false
		default:
			return nil
		}
	}
}

private struct OutboundMessageInvocation {
	let outbound: OutboundTextCommand
	let isOperatorMessage: Bool
	let isSecretMessage: Bool

	init?(command: String, silentlyConnecting: Bool) {
		guard let policy = OutboundMessageCommandPolicy(
			command: command,
			silentlyConnecting: silentlyConnecting
		), let outbound = OutboundTextCommand(policy.remoteCommand)
		else { return nil }
		self.outbound = outbound
		isOperatorMessage = policy.isOperatorMessage
		isSecretMessage = policy.isSecretMessage
	}
}

public extension IRCClient {
	@MainActor
	internal func dispatchMessageCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.command.lowercased()
		let silentlyConnecting = isPerformingConnectCommands && config.runConnectCommandsSilently
		guard let invocation = OutboundMessageInvocation(
			command: command,
			silentlyConnecting: silentlyConnecting
		) else { return false }
		guard isLoggedIn else {
			printDebugInformation(toConsole: IRCTransportStrings.notConnected)
			return true
		}

		let arguments = NSMutableAttributedString(attributedString: parsed.arguments)
		let operatorPrefix: String?
		if invocation.isOperatorMessage {
			guard let prefix = supportInfo.statusMessagePrefix(forModeSymbol: "o") else {
				printDebugInformation(IRCTransportStrings.operatorMessageUnsupported)
				return true
			}
			operatorPrefix = prefix
		} else {
			operatorPrefix = nil
		}

		let targetName: String
		if invocation.isSecretMessage == false, invocation.outbound.lineType == .action,
		   let targetChannel
		{
			guard targetChannel.isUtility == false else {
				printDebugInformation(IRCCommandStrings.commandUnavailableInWindow)
				return true
			}
			if targetChannel.isDirectChat {
				if arguments.length == 0 {
					arguments.append(NSAttributedString(string: " "))
				}
				sendDirectChatText(arguments, as: .privmsgAction, to: targetChannel)
				return true
			}
			targetName = targetChannel.name
		} else if invocation.isOperatorMessage,
		          stringIsChannelName(arguments.string) == false,
		          targetChannel?.isChannel == true,
		          let targetChannel
		{
			targetName = targetChannel.name
		} else {
			targetName = arguments.ceTokenAsString
		}
		guard requireArguments(targetName, for: parsed.command) else { return true }

		if arguments.length == 0 {
			guard invocation.outbound.lineType == .action else { return true }
			arguments.append(NSAttributedString(string: " "))
		}

		var destinations = targetName.components(separatedBy: ",")
		var destinationToSelect: IRCChannel?
		if invocation.isSecretMessage == false, silentlyConnecting == false,
		   operatorPrefix == nil,
		   supportInfo.maximumTargets(forCommand: invocation.outbound.wireCommand) > 1
		{
			let groupedChannels = destinations.compactMap { destinationName -> IRCChannel? in
				guard let channel = self.findChannel(destinationName), channel.isChannel, channel.isActive else {
					return nil
				}
				return channel
			}
			if groupedChannels.count > 1 {
				sendText(arguments, as: remoteCommand(for: invocation.outbound), toChannels: groupedChannels)
				if TextualPreferences.giveFocusOnMessageCommand() {
					destinationToSelect = groupedChannels.first
				}
				let groupedNames = Set(groupedChannels.map(\.name))
				destinations.removeAll { groupedNames.contains($0) }
			}
		}

		for destination in destinations {
			let selected = sendCommandText(
				arguments,
				to: destination,
				operatorPrefix: operatorPrefix,
				invocation: invocation,
				localCommand: parsed.command,
				silentlyConnecting: silentlyConnecting
			)
			if destinationToSelect == nil, TextualPreferences.giveFocusOnMessageCommand() {
				destinationToSelect = selected
			}
		}
		selectCommandDestination(destinationToSelect)
		return true
	}

	@objc(inputText:destination:)
	@MainActor
	func inputText(_ input: Any, destination: IRCTreeItem) {
		inputText(input, as: .privmsg, destination: destination)
	}

	@objc(inputText:asCommand:)
	@MainActor
	func inputText(_ input: Any, as command: IRCRemoteCommand) {
		guard let destination = NSObject.applicationController().mainWindow.selectedItem else { return }
		inputText(input, as: command, destination: destination)
	}

	@objc(inputText:asCommand:destination:)
	@MainActor
	func inputText(_ input: Any, as command: IRCRemoteCommand, destination: IRCTreeItem) {
		guard isTerminating == false, let text = attributedInput(input), text.length > 0 else { return }
		guard OutboundTextCommand(command) != nil else {
			assertionFailure("Unsupported outbound text command")
			return
		}

		let lines = text.ceSplitIntoLines
		let shouldWarn = lines.count > 4 || text.length > 2040
		if shouldWarn, shouldContinuePotentialFlood() == false {
			return
		}

		for originalLine in lines {
			var line = originalLine
			let source = line.string
			let isPrefixed = source.hasPrefix("/")

			if destination.isClient {
				if isPrefixed {
					line = line.ce_attributedSubstring(from: 1)
				}
				sendCommand(line)
				continue
			}

			guard let channel = (destination as AnyObject) as? IRCChannel else {
				assertionFailure("Non-client IRC tree destinations must be channels")
				continue
			}

			if isPrefixed, source.hasPrefix("//") == false, line.length > 1 {
				sendCommand(line.ce_attributedSubstring(from: 1))
			} else {
				if isPrefixed, line.length > 1 {
					line = line.ce_attributedSubstring(from: 1)
				}
				sendText(line, as: command, to: channel)
			}
		}
	}

	@objc(sendText:asCommand:toChannel:)
	@MainActor
	func sendText(_ text: NSAttributedString, as command: IRCRemoteCommand, to channel: IRCChannel) {
		guard text.length > 0 else { return }
		guard channel.isUtility == false else {
			printDebugInformation(IRCTransportStrings.messagesUnavailableInWindow, in: channel)
			return
		}
		guard channel.isDirectChat == false else {
			sendDirectChatText(text, as: command, to: channel)
			return
		}
		guard let outbound = OutboundTextCommand(command) else { return }

		localUserSentMessage(in: channel)
		var replyIdentifier = nextMessageReplyIdentifier
		nextMessageReplyIdentifier = nil
		if isCapabilityEnabled(.messageTags) == false {
			replyIdentifier = nil
		}

		for line in text.ceSplitIntoLines {
			let mutableLine = NSMutableAttributedString(attributedString: line)
			while mutableLine.length > 0 {
				let lengthBeforeFormatting = mutableLine.length
				let message = mutableLine.stringFormatted(
					forChannel: channel.name,
					on: self,
					with: outbound.lineType
				)

				// Defensive: `stringFormatted` guarantees progress, but this
				// loop must never spin if that ever stops being true.
				guard mutableLine.length < lengthBeforeFormatting else { break }
				let lineReplyIdentifier = replyIdentifier
				replyIdentifier = nil
				nextLineReplyToMessageIdentifier = lineReplyIdentifier

				let redactedMessage = IRCClient.redactedServiceMessage(message, sentTo: channel.name)
				let deliveryLabel = printLocallyIfNeeded(
					redactedMessage,
					channel: channel,
					outbound: outbound
				)

				let wireMessage = outbound.lineType == .action ? "\u{01}ACTION \(message)\u{01}" : message
				nextLineReplyToMessageIdentifier = nil

				var tags: [String: String] = [:]
				if let deliveryLabel {
					tags["label"] = deliveryLabel
				}
				if let lineReplyIdentifier {
					tags["+draft/reply"] = lineReplyIdentifier
				}

				if tags.isEmpty {
					send(outbound.wireCommand, arguments: [channel.name, wireMessage])
				} else {
					sendCommand(outbound.wireCommand, arguments: [channel.name, wireMessage], tags: tags)
				}
			}
		}

		processBundlesUserMessage(text.string, command: outbound.wireCommand)
	}

	@objc(sendText:asCommand:toChannels:)
	@MainActor
	func sendText(_ text: NSAttributedString, as command: IRCRemoteCommand, toChannels channels: [IRCChannel]) {
		guard text.length > 0, channels.isEmpty == false, let outbound = OutboundTextCommand(command) else { return }
		let targetLimit = supportInfo.maximumTargets(forCommand: outbound.wireCommand)
		var groupedChannels: [IRCChannel] = []
		for channel in channels {
			if targetLimit > 1, channel.isChannel {
				groupedChannels.append(channel)
			} else {
				sendText(text, as: command, to: channel)
			}
		}
		guard groupedChannels.isEmpty == false else { return }
		let targetGroups = IRCISupportInfo.chunkTargets(groupedChannels.map(\.name), limit: targetLimit)
		let echoMessageEnabled = isCapabilityEnabled(.echoMessage)
		var groupOffset = 0
		for targetGroup in targetGroups {
			let groupChannels = Array(groupedChannels[groupOffset ..< groupOffset + targetGroup.count])
			groupOffset += targetGroup.count
			let targetList = targetGroup.joined(separator: ",")
			for line in text.ceSplitIntoLines {
				let mutableLine = NSMutableAttributedString(attributedString: line)
				while mutableLine.length > 0 {
					let lengthBeforeFormatting = mutableLine.length
					let message = mutableLine.stringFormatted(
						forChannel: targetList,
						on: self,
						with: outbound.lineType
					)

					guard mutableLine.length < lengthBeforeFormatting else { break }
					if echoMessageEnabled == false {
						for channel in groupChannels {
							_ = printLocallyIfNeeded(
								Self.redactedServiceMessage(message, sentTo: channel.name),
								channel: channel,
								outbound: outbound
							)
						}
					}
					let wireMessage = outbound.lineType == .action
						? CTCPPayload.framed(command: "ACTION", text: message, sanitizingLineBreaks: false)
						: message
					send(outbound.wireCommand, arguments: [targetList, wireMessage])
				}
			}
		}
		processBundlesUserMessage(text.string, command: outbound.wireCommand)
	}

	private func attributedInput(_ input: Any) -> NSAttributedString? {
		if let text = input as? String {
			return NSAttributedString(string: text)
		}
		if let text = input as? NSAttributedString {
			return text
		}
		assertionFailure("Input must be String or NSAttributedString")
		return nil
	}

	private func shouldContinuePotentialFlood() -> Bool {
		potentialFloodAlert()
	}

	private func potentialFloodAlert() -> Bool {
		TDCAlert.modalAlert(
			withMessage: IRCTransportStrings.confirmLargeMessage,
			title: IRCTransportStrings.largeMessageWarning,
			defaultButton: PromptStrings.Action.yes,
			alternateButton: PromptStrings.Action.no,
			suppressionKey: "input_text_possible_flood_warning",
			suppressionText: nil
		)
	}

	private func printLocallyIfNeeded(
		_ message: String,
		channel: IRCChannel,
		outbound: OutboundTextCommand,
		localCommand: String? = nil
	) -> String? {
		if isCapabilityEnabled(.echoMessage) {
			guard labeledResponseTrackingEnabled() else { return nil }
			guard let label = registerPendingDelivery(for: channel) else { return nil }
			nextLineDeliveryState = .pending
			print(
				message,
				by: userNickname,
				in: channel,
				as: outbound.lineType,
				command: localCommand ?? outbound.wireCommand,
				receivedAt: Date(),
				isEncrypted: false,
				referenceMessage: nil
			) { [weak self] context in
				self?.attachLineNumber(context.lineNumber, toDeliveryWithLabel: label)
			}
			return label
		}

		print(
			message,
			by: userNickname,
			in: channel,
			as: outbound.lineType,
			command: localCommand ?? outbound.wireCommand,
			receivedAt: Date(),
			isEncrypted: false
		)
		return nil
	}

	@MainActor
	private func sendCommandText(
		_ text: NSAttributedString,
		to rawDestination: String,
		operatorPrefix: String?,
		invocation: OutboundMessageInvocation,
		localCommand: String,
		silentlyConnecting: Bool
	) -> IRCChannel? {
		let explicitPrefix = supportInfo.extractStatusMessagePrefix(fromChannelNamed: rawDestination)
		let prefix = explicitPrefix.isEmpty ? operatorPrefix : explicitPrefix
		let destinationName = explicitPrefix.isEmpty ? rawDestination : String(rawDestination.dropFirst())
		var channel = findChannel(destinationName)
		if invocation.isSecretMessage == false, channel == nil, stringIsNickname(destinationName) {
			channel = NSObject.applicationController().world.createPrivateMessage(destinationName, on: self)
		}

		let destinationIsChannel = channel?.isChannel == true ||
			(channel == nil && stringIsChannelName(destinationName))
		let wireTarget = prefix.flatMap { destinationIsChannel ? "\($0)\(destinationName)" : nil }
			?? destinationName
		let remainingText = NSMutableAttributedString(attributedString: text)
		while remainingText.length > 0 {
			let lengthBeforeFormatting = remainingText.length
			let message = remainingText.stringFormatted(
				forChannel: wireTarget,
				on: self,
				with: invocation.outbound.lineType
			)

			guard remainingText.length < lengthBeforeFormatting else { break }
			let redactedMessage = Self.redactedServiceMessage(message, sentTo: wireTarget)
			let deliveryLabel: String?
			if silentlyConnecting {
				printDebugInformation(
					toConsole: IRCTransportStrings.connectCommand(target: wireTarget, redactedMessage: redactedMessage)
				)
				deliveryLabel = nil
			} else if let channel, invocation.isSecretMessage == false {
				deliveryLabel = printLocallyIfNeeded(
					redactedMessage,
					channel: channel,
					outbound: invocation.outbound,
					localCommand: localCommand
				)
			} else {
				deliveryLabel = nil
			}

			let wireMessage = invocation.outbound.lineType == .action
				? CTCPPayload.framed(command: "ACTION", text: message, sanitizingLineBreaks: false)
				: message
			if let deliveryLabel {
				sendCommand(
					invocation.outbound.wireCommand,
					arguments: [wireTarget, wireMessage],
					tags: ["label": deliveryLabel]
				)
			} else {
				send(invocation.outbound.wireCommand, arguments: [wireTarget, wireMessage])
			}
		}
		return invocation.isSecretMessage ? nil : channel
	}

	private func remoteCommand(for outbound: OutboundTextCommand) -> IRCRemoteCommand {
		switch outbound.lineType {
		case .action: .privmsgAction
		case .notice: .notice
		default: .privmsg
		}
	}

	@MainActor
	private func selectCommandDestination(_ channel: IRCChannel?) {
		guard let channel,
		      let treeItem = (channel as AnyObject) as? IRCTreeItem
		else { return }
		NSObject.applicationController().mainWindow.select(treeItem)
	}
}
