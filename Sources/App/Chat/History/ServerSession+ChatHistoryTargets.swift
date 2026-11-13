// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A `CHATHISTORY TARGETS` request waiting for its batch.
final class PendingTargetsSweep {
	enum Reason: Equatable {
		/// After registration: opens up to the automatic cap and lists the rest.
		case automatic
		/// `/chathistory targets`: lists every target and opens up to `limit`.
		case command(limit: Int)
	}

	let reason: Reason
	let label: String?
	let connectionIdentifier: String?
	var timeoutTimer: SessionTimer?

	init(reason: Reason, label: String?, connectionIdentifier: String?) {
		self.reason = reason
		self.label = label
		self.connectionIdentifier = connectionIdentifier
	}

	isolated deinit { timeoutTimer?.stop() }
}

/** Direct conversations that had messages while the session was away.

 A message from someone with no open conversation is in the server's history
 but nothing asks for it, because history is fetched per conversation. One
 `TARGETS` request after registration lists the conversations active since the
 session last saw a message, and the latest page of each new direct one is
 asked for. The page arrives as ordinary private messages, so the address
 book's ignore rules judge each sender by its real hostmask, and a conversation
 opens, unselected, only for messages that pass them. */
extension ServerSession {
	/// Whether the automatic sweep applies to this connection.
	var discoversMissedDirectMessages: Bool {
		environment.settings.requestChatHistory && environment.settings.discoverMissedDirectMessages
			&& isCapabilityEnabled(.chatHistory) && config.lastMessageServerTime > 0
			&& chatHistory.refusesTargets == false
			/* An unbound bouncer account connection lists networks, not
			 conversations; each network connection sweeps for itself. */
			&& (isCapabilityEnabled(.bouncerNetworks) == false || config.bouncerNetwork != nil)
	}

	/// Schedules the sweep shortly after registration, so the catch-ups the
	/// autojoin starts go out first.
	func scheduleChatHistoryTargetsSweep() {
		chatHistory.targetsSweepTimer?.stop()
		guard discoversMissedDirectMessages else { return }
		chatHistory.targetsSweepTimer = SessionTimer.once(after: 2) { [weak self] in
			guard let self, isLoggedIn, discoversMissedDirectMessages else { return }
			let since = Date(timeIntervalSince1970: config.lastMessageServerTime)
			requestChatHistoryTargets(since: since, reason: .automatic)
		}
	}

	/** Asks for the conversations active since `since`.

	 The bounds go newest first — BETWEEN semantics — so a server that cuts
	 the list at the limit keeps the most recently active. Both are moved
	 outwards a little for clock skew. */
	@discardableResult
	func requestChatHistoryTargets(since: Date, reason: PendingTargetsSweep.Reason, limit requested: UInt? = nil) -> Bool {
		guard isLoggedIn, isCapabilityEnabled(.chatHistory), chatHistory.targetsSweep == nil else { return false }
		let limit = ChatHistoryLimit.clamp(
			requested ?? ChatHistoryTargetsPolicy.requestLimit,
			serverMaximum: supportInfo.chatHistoryMaximumLines
		)
		let command = ChatHistoryCommand.targets(
			from: Date().addingTimeInterval(ChatHistoryTargetsPolicy.timestampFuzz),
			to: since.addingTimeInterval(-ChatHistoryTargetsPolicy.timestampFuzz),
			limit: limit
		)
		guard let arguments = try? command.arguments(support: ChatHistoryReferenceSupport()) else { return false }
		let label = labeledResponseTrackingEnabled() ? ChatHistoryPolicy.targetsLabelPrefix + UUID().uuidString : nil
		let sweep = PendingTargetsSweep(reason: reason, label: label, connectionIdentifier: socket?.uniqueIdentifier)
		sweep.timeoutTimer = SessionTimer.once(after: ChatHistoryPolicy.requestTimeout) { [weak self, weak sweep] in
			guard let self, let sweep, chatHistory.targetsSweep === sweep else { return }
			chatHistory.targetsSweep = nil
		}
		chatHistory.targetsSweep = sweep
		sendCommand(.chathistory, arguments: arguments, tags: label.map { ["label": $0] })
		return true
	}

	/// Whether a FAIL answers the sweep; it ends it, and an automatic sweep
	/// is not tried again on this connection.
	func noteChatHistoryTargetsFailure(_ message: Message, label: String?) -> Bool {
		guard let sweep = chatHistory.targetsSweep,
		      message.param(at: 2).uppercased() == "TARGETS" || (label != nil && label == sweep.label)
		else { return false }
		sweep.timeoutTimer?.stop()
		chatHistory.targetsSweep = nil
		chatHistory.refusesTargets = true
		if case .command = sweep.reason {
			printDebugInformation(toConsole: String(localized: .ChatHistory.chatHistoryTargetsRefused(message.params.last ?? "")))
		}
		return true
	}

	/** A `draft/chathistory-targets` batch: the conversations it lists, opened
	 or listed as the sweep that asked for them wants. A batch nothing asked
	 for is dropped. */
	func receiveChatHistoryTargetsBatch(_ batch: MessageBatch, contents: MessageBatch) {
		defer { batchMessages.dequeueEntry(contents) }
		guard let sweep = chatHistory.targetsSweep,
		      sweep.connectionIdentifier == socket?.uniqueIdentifier,
		      sweep.label == nil || sweep.label == batch.labeledResponseBatch?.labeledDelivery.label
		else { return }
		sweep.timeoutTimer?.stop()
		chatHistory.targetsSweep = nil

		let targets = contents.queuedMessages
			.filter { $0.remoteCommand == .chathistory && batchMessage(ofKind: .chatHistoryTargets, containing: $0) === batch }
			.compactMap { ChatHistoryTarget(parameters: $0.params) }
		let cap = switch sweep.reason {
		case .automatic: ChatHistoryTargetsPolicy.maximumDiscoveredConversations
		case let .command(limit): limit
		}
		let found = ChatHistoryTargetsPolicy.discovered(
			targets,
			isChannel: { [unowned self] in stringIsChannelName($0) },
			isSelf: { [unowned self] in nicknameIsMyself($0) },
			/* Only a rule written against the nickname can be judged from a name
				alone. Rules on the host are applied to the messages themselves. */
			isIgnored: { [unowned self] in findAddressBookEntry(forHostmask: "\($0)!*@*")?.ignorePrivateMessages == true },
			hasConversation: { [unowned self] in findConversation($0) != nil },
			cap: cap
		)
		for name in found.open {
			let command = ChatHistoryCommand.latest(target: name, after: .unbounded, limit: chatHistoryRequestLimit())
			guard let arguments = chatHistoryArguments(command) else { continue }
			send(.chathistory, arguments: arguments)
		}

		switch sweep.reason {
		case .automatic:
			if found.overflow.isEmpty == false {
				printDebugInformation(toConsole: String(localized: .ChatHistory.chatHistoryTargetsOverflow(
					found.overflow.joined(separator: ", ")
				)))
			}
		case .command:
			printChatHistoryTargets(targets, opened: found.open.count)
		}
	}

	private func printChatHistoryTargets(_ targets: [ChatHistoryTarget], opened: Int) {
		guard targets.isEmpty == false else {
			printDebugInformation(toConsole: String(localized: .ChatHistory.chatHistoryTargetsNone))
			return
		}
		for target in targets {
			printDebugInformation(toConsole: String(localized: .ChatHistory.chatHistoryTargetsLine(
				target.name,
				target.latest.formatted(date: .abbreviated, time: .shortened)
			)))
		}
		if opened > 0 {
			printDebugInformation(toConsole: String(localized: .ChatHistory.chatHistoryTargetsOpened(opened)))
		}
	}

	func resetChatHistoryTargets() {
		chatHistory.targetsSweepTimer?.stop()
		chatHistory.targetsSweepTimer = nil
		chatHistory.targetsSweep?.timeoutTimer?.stop()
		chatHistory.targetsSweep = nil
		chatHistory.refusesTargets = false
	}
}

extension ChatHistoryPolicy {
	static let targetsLabelPrefix = "targets-"
}
