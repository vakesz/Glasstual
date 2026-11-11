// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

private enum OutboundTextSuppressionKey: String {
	case potentialFlood = "Input Text Possible Flood Warning"
}

/// Where `dispatchMessageCommand` sends its text.
private enum MessageTarget {
	case sentDirectly
	case refused
	case named(String)
}

extension ServerSession {
	/// An empty ACTION would be dropped by most servers, so it goes out with a
	/// single space instead.
	private static func actionBody(_ body: NSAttributedString) -> NSAttributedString {
		body.length == 0 ? NSAttributedString(string: " ") : body
	}

	func dispatchMessageCommand(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		let silentlyConnecting = isPerformingConnectCommands && config.runConnectCommandsSilently
		guard let policy = OutboundMessageOptions(
			command: parsed.localCommand,
			silentlyConnecting: silentlyConnecting
		) else { return }
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return
		}

		var cursor = parsed.arguments
		let operatorPrefix: String?
		if policy.isOperatorMessage {
			guard let prefix = supportInfo.statusMessagePrefix(forModeSymbol: "o") else {
				printDebugInformation(String(localized: .IRC.cannotSendOperatorMessageBecause))
				return
			}
			operatorPrefix = prefix
		} else {
			operatorPrefix = nil
		}

		let targetName: String
		switch resolveMessageTarget(cursor: &cursor, policy: policy, targetConversation: targetConversation) {
		case .sentDirectly, .refused:
			return
		case let .named(name):
			targetName = name
		}
		guard requireArguments(targetName, for: parsed.command) else { return }

		let body = cursor.attributedRest
		if body.length == 0, policy.lineType != .action {
			return
		}
		let arguments = Self.actionBody(body)

		var destinations = targetName.components(separatedBy: ",")
		var destinationToSelect: Conversation?
		if policy.isSecretMessage == false, silentlyConnecting == false,
		   operatorPrefix == nil,
		   supportInfo.groupsMultipleTargets(forCommand: policy.remoteCommand.wireName)
		{
			destinationToSelect = sendToGroupedChannels(arguments, destinations: &destinations, policy: policy)
		}

		for destination in destinations {
			let selected = sendCommandText(
				arguments,
				to: destination,
				operatorPrefix: operatorPrefix,
				policy: policy,
				localCommand: parsed.command,
				silentlyConnecting: silentlyConnecting
			)
			if destinationToSelect == nil, environment.settings.giveFocusOnMessageCommand {
				destinationToSelect = selected
			}
		}
		selectCommandDestination(destinationToSelect)
	}

	/// Who the message goes to. An action in a direct chat is sent from here,
	/// and an action in the console is refused.
	private func resolveMessageTarget(
		cursor: inout CommandArguments,
		policy: OutboundMessageOptions,
		targetConversation: Conversation?
	) -> MessageTarget {
		if policy.isSecretMessage == false, policy.lineType == .action,
		   let targetConversation
		{
			guard targetConversation.isConsole == false else {
				printDebugInformation(String(localized: .IRC.thisCommandCannotBeUsedWithin))
				return .refused
			}
			if targetConversation.isDirectChat {
				// An empty action still has to carry a body onto the wire.
				sendDirectChatText(Self.actionBody(cursor.attributedRest), as: .privmsgAction, to: targetConversation)
				return .sentDirectly
			}
			return .named(targetConversation.name)
		} else if policy.isOperatorMessage,
		          stringIsChannelName(cursor.rest) == false,
		          targetConversation?.isChannel == true,
		          let targetConversation
		{
			return .named(targetConversation.name)
		} else {
			return .named(cursor.next())
		}
	}

	/** Sends one line to every active channel among `destinations` and takes
	 them out of the list. Returns the channel to select, if any.

	 Channels are found under the server's casemapping, so `#Chat` and
	 `#chat` are one channel: it is grouped once, and every spelling of it
	 is taken out of the per-destination loop. Matching the typed names
	 against the channels' own spelling left `#Chat` behind and sent the
	 message a second time. */
	private func sendToGroupedChannels(
		_ arguments: NSAttributedString,
		destinations: inout [String],
		policy: OutboundMessageOptions
	) -> Conversation? {
		var groupedChannels: [Conversation] = []
		var groupedIdentities: Set<ObjectIdentifier> = []
		for destinationName in destinations {
			guard let channel = findConversation(destinationName), channel.isChannel, channel.isActive,
			      groupedIdentities.insert(ObjectIdentifier(channel)).inserted
			else { continue }
			groupedChannels.append(channel)
		}
		guard groupedChannels.count > 1 else { return nil }
		sendText(arguments, as: policy.remoteCommand, toConversations: groupedChannels)
		destinations.removeAll { destinationName in
			findConversation(destinationName).map { groupedIdentities.contains(ObjectIdentifier($0)) } ?? false
		}
		return environment.settings.giveFocusOnMessageCommand ? groupedChannels.first : nil
	}

	func inputText(_ input: String, as command: RemoteCommand = .privmsg, destination: ChatItem) {
		inputText(NSAttributedString(string: input), as: command, destination: destination)
	}

	func inputText(_ text: NSAttributedString, as command: RemoteCommand = .privmsg, destination: ChatItem) {
		guard isTerminating == false, text.length > 0 else { return }
		guard OutboundMessageOptions(remoteCommand: command) != nil else {
			assertionFailure("Unsupported outbound text command")
			return
		}

		let source = NSAttributedString(attributedString: text)
		let replyIdentifier = replies.takeForMessage()
		if let conversation = destination as? Conversation,
		   let proposal = multilineProposal(for: source, as: command, in: conversation)
		{
			/* One question replaces the flood warning: the person has been shown
			 how the text will go out and chooses between the ways. */
			requestMultilineChoice(
				proposal,
				text: source,
				as: command,
				in: conversation,
				replyIdentifier: replyIdentifier
			)
			return
		}
		var warningCursor = OutboundInputCursor(source)
		var lineCount = 0
		while lineCount <= 4, warningCursor.next() != nil {
			lineCount += 1
		}
		let shouldWarn = lineCount > 4 || source.length > 2040
		if shouldWarn {
			let destinationName = destination.name
			requestConfirmation(Self.potentialFloodAlert, isCurrent: { session in
				destination === session || (destination.name == destinationName &&
					session.conversationList.contains { $0 === destination })
			}, perform: { session in
				session.sendInputLines(source, as: command, destination: destination, replyIdentifier: replyIdentifier)
			})
			return
		}
		sendInputLines(source, as: command, destination: destination, replyIdentifier: replyIdentifier)
	}

	func sendInputLines(_ text: NSAttributedString, as command: RemoteCommand, destination: ChatItem,
	                    replyIdentifier: String?)
	{
		var remaining = OutboundInputCursor(text)
		var pendingReply = replyIdentifier
		enqueueOutboundText(conversations: (destination as? Conversation).map { [$0] } ?? []) { [weak destination] session in
			guard let destination, let originalLine = remaining.next() else { return false }
			let laterReply = session.replies.nextMessage
			session.replies.nextMessage = pendingReply
			defer {
				pendingReply = session.replies.nextMessage
				session.replies.nextMessage = laterReply
			}
			var line = originalLine
			let source = line.string
			let isPrefixed = source.hasPrefix("/")

			if destination.isSession {
				if isPrefixed {
					line = line.attributedSubstring(fromIndex: 1)
				}
				session.sendCommand(line, completeTarget: false)
				return true
			}

			guard let conversation = destination as? Conversation else {
				assertionFailure("A sidebar destination is either the session itself or a conversation")
				return false
			}

			if isPrefixed, source.hasPrefix("//") == false, line.length > 1 {
				session.sendCommand(line.attributedSubstring(fromIndex: 1), target: conversation.name)
			} else {
				if isPrefixed, line.length > 1 {
					line = line.attributedSubstring(fromIndex: 1)
				}
				session.sendText(line, as: command, to: conversation)
			}
			return true
		}
	}

	func sendText(_ text: NSAttributedString, as command: RemoteCommand, to conversation: Conversation) {
		guard text.length > 0 else { return }
		guard conversation.isConsole == false else {
			printDebugInformation(String(localized: .IRC.messagesCannotBeSent), in: conversation)
			return
		}
		guard conversation.isDirectChat == false else {
			sendDirectChatText(text, as: command, to: conversation)
			return
		}
		guard let policy = OutboundMessageOptions(remoteCommand: command) else { return }

		typingSender.finish(in: conversation)
		var replyIdentifier = replies.takeForMessage()
		if isCapabilityEnabled(.messageTags) == false {
			replyIdentifier = nil
		}

		var cursor = OutboundTextCursor(text)
		enqueueOutboundText(conversations: [conversation]) { session in
			guard let message = cursor.next(for: conversation.name, on: session, as: policy.lineType) else {
				return false
			}
			let lineReplyIdentifier = replyIdentifier
			replyIdentifier = nil
			session.replies.nextPrintedLine = lineReplyIdentifier

			let redactedMessage = WireRedaction.redactedServiceMessage(message, sentTo: conversation.name)
			let deliveryLabel = session.printLocallyIfNeeded(redactedMessage, in: conversation, policy: policy)
			let wireMessage = policy.lineType == .action ? CTCPPayload.action(message) : message
			session.replies.nextPrintedLine = nil

			var tags: [String: String] = [:]
			if let deliveryLabel {
				tags["label"] = deliveryLabel
			}
			if let lineReplyIdentifier {
				tags["+draft/reply"] = lineReplyIdentifier
			}
			if tags.isEmpty {
				session.send(policy.remoteCommand, arguments: [conversation.name, wireMessage])
			} else {
				session.sendCommand(policy.remoteCommand, arguments: [conversation.name, wireMessage], tags: tags)
			}
			return true
		}
	}

	func sendText(_ text: NSAttributedString, as command: RemoteCommand, toConversations conversations: [Conversation]) {
		guard text.length > 0, conversations.isEmpty == false,
		      let policy = OutboundMessageOptions(remoteCommand: command) else { return }
		/* Grouping needs the server's word for it: without an advertised limit
		 above one, every channel gets its own line. A direct conversation is
		 never grouped even where the server would take the targets, because the
		 transcript the user reads is per-conversation. */
		let groupsTargets = supportInfo.groupsMultipleTargets(forCommand: policy.remoteCommand.wireName)
		let targetLimit = supportInfo.maximumTargets(forCommand: policy.remoteCommand.wireName)
		var groupedChannels: [Conversation] = []
		for conversation in conversations {
			if groupsTargets, conversation.isChannel {
				groupedChannels.append(conversation)
			} else {
				sendText(text, as: command, to: conversation)
			}
		}
		guard groupedChannels.isEmpty == false else { return }
		let targetGroups = WireBatching.chunkTargets(groupedChannels.map(\.name), limit: targetLimit)
		var groupOffset = 0
		var groupIndex = 0
		let source = NSAttributedString(attributedString: text)
		var cursor = OutboundTextCursor(source)
		enqueueOutboundText(conversations: groupedChannels) { session in
			while groupIndex < targetGroups.count {
				let targetGroup = targetGroups[groupIndex]
				let groupChannels = Array(groupedChannels[groupOffset ..< groupOffset + targetGroup.count])
				let targetList = targetGroup.joined(separator: ",")
				if let message = cursor.next(for: targetList, on: session, as: policy.lineType) {
					/* One command carries one label, so only the first channel in
					 the group registers a delivery; the rest print untracked. The
					 label used to be discarded here, which left every grouped
					 message uncorrelated. */
					var deliveryLabel: String?
					for (index, channel) in groupChannels.enumerated() {
						/* The echo of a comma list is filed nowhere, so this print
						 is the only one the message gets. */
						let label = session.printLocallyIfNeeded(
							WireRedaction.redactedServiceMessage(message, sentTo: channel.name),
							in: channel,
							policy: policy,
							registeringDelivery: index == 0,
							echoReturnsHere: false
						)

						if index == 0 {
							deliveryLabel = label
						}
					}
					let wireMessage = policy.lineType == .action
						? CTCPPayload.action(message)
						: message
					if let deliveryLabel {
						session.sendCommand(
							policy.remoteCommand,
							arguments: [targetList, wireMessage],
							tags: ["label": deliveryLabel]
						)
					} else {
						session.send(policy.remoteCommand, arguments: [targetList, wireMessage])
					}
					return true
				}
				groupIndex += 1
				groupOffset += targetGroup.count
				cursor = OutboundTextCursor(source)
			}
			return false
		}
	}

	/** The confirmation for a message large enough to flood the conversation.

	 Send/Cancel, not Yes/No: the question is whether to send, so the button
	 that does it says so -- and the one that answers Escape says that nothing
	 was sent. */
	private static var potentialFloodAlert: AlertRequest {
		AlertRequest(
			title: String(localized: .IRC.messageThatYouAreSending),
			body: String(localized: .IRC.areYouSureYouWant),
			defaultButton: PromptStrings.Action.send,
			alternateButton: PromptStrings.Action.cancel,
			suppressionKey: OutboundTextSuppressionKey.potentialFlood.rawValue,
			style: .warning
		)
	}

	func printLocallyIfNeeded(
		_ message: String,
		in conversation: Conversation,
		policy: OutboundMessageOptions,
		localCommand: String? = nil,
		statusMessageTarget: String? = nil,
		registeringDelivery: Bool = true,
		echoReturnsHere: Bool = true
	) -> String? {
		/* With echo-message the server sends this message back and the inbound
		 path prints it, so printing here too would show it twice -- unless a
		 label lets the echo be matched to the line printed now. */
		if isCapabilityEnabled(.echoMessage), labeledResponseTrackingEnabled() == false {
			return nil
		}

		let label = registeringDelivery ? registerPendingDelivery(for: conversation) : nil

		/* Every label is taken, so the line goes out without one and nothing can
		 match its echo to a line printed now. The echo prints instead, once. */
		if label == nil, registeringDelivery, echoReturnsHere, isCapabilityEnabled(.echoMessage) {
			return nil
		}

		print(
			message,
			by: userNickname,
			in: conversation,
			as: policy.lineType,
			command: localCommand ?? policy.remoteCommand.wireName,
			receivedAt: Date(),
			isEncrypted: false,
			referenceMessage: nil,
			deliveryLabel: label,
			statusMessageTarget: statusMessageTarget
		)

		return label
	}

	private func sendCommandText(
		_ text: NSAttributedString,
		to rawDestination: String,
		operatorPrefix: String?,
		policy: OutboundMessageOptions,
		localCommand: String,
		silentlyConnecting: Bool
	) -> Conversation? {
		let explicitPrefix = supportInfo.extractStatusMessagePrefix(fromTargetNamed: rawDestination)
		let prefix = explicitPrefix.isEmpty ? operatorPrefix : explicitPrefix
		let destinationName = explicitPrefix.isEmpty ? rawDestination : String(rawDestination.dropFirst())
		var conversation = findConversation(destinationName)
		if policy.isSecretMessage == false, conversation == nil, stringIsNickname(destinationName) {
			conversation = chatSession?.createDirectConversation(destinationName, on: self)
		}

		let destinationIsChannel = conversation?.isChannel == true ||
			(conversation == nil && stringIsChannelName(destinationName))
		let statusMessageTarget = prefix.flatMap { destinationIsChannel ? "\($0)\(destinationName)" : nil }
		let wireTarget = statusMessageTarget ?? destinationName
		var cursor = LineCursor(text)
		enqueueOutboundText(conversations: conversation.map { [$0] } ?? []) { session in
			guard let message = cursor.nextLine(forTarget: wireTarget, on: session, with: policy.lineType)
			else { return false }
			let redactedMessage = WireRedaction.redactedServiceMessage(message, sentTo: wireTarget)
			let tags: [String: String]?
			if silentlyConnecting || policy.isSecretMessage {
				/* Its echo would print what was meant to stay unprinted, so a
				 line that cannot be tracked is not sent, nor is the rest. */
				guard let unprintedTags = session.noteUnprintedSend(
					to: destinationName,
					text: message,
					lineType: policy.lineType
				) else {
					session.printDebugInformation(toConsole: ConnectionSafetyStrings.Wire.unprintedLinesHeldBack)
					return false
				}
				tags = unprintedTags
				if silentlyConnecting {
					session.printDebugInformation(
						toConsole: String(localized: .IRC.connectCommandSent(wireTarget, redactedMessage))
					)
				}
			} else if let conversation {
				tags = session.printLocallyIfNeeded(
					redactedMessage,
					in: conversation,
					policy: policy,
					localCommand: localCommand,
					statusMessageTarget: statusMessageTarget
				).map { ["label": $0] }
			} else {
				tags = nil
			}

			let wireMessage = policy.lineType == .action
				? CTCPPayload.action(message)
				: message
			session.sendCommand(policy.remoteCommand, arguments: [wireTarget, wireMessage], tags: tags)
			return true
		}
		return policy.isSecretMessage ? nil : conversation
	}

	private func selectCommandDestination(_ conversation: Conversation?) {
		guard let conversation else { return }
		output?.select(conversation)
	}
}
