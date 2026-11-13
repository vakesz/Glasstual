// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	/// Labeled responses require batch support. Their label tag does not require
	/// the separate message-tags capability, which enables client-only tags.
	func labeledResponseTrackingEnabled() -> Bool {
		isCapabilityEnabled(.labeledResponse) && isCapabilityEnabled(.batch)
	}

	func nextMessageLabel() -> String {
		labeledResponses.counter += 1
		return "g\(labeledResponses.counter)"
	}

	func registerPendingDelivery(for conversation: Conversation?) -> String? {
		guard labeledResponseTrackingEnabled(),
		      labeledResponses.pending.count < LabeledResponsePolicy.maximumPendingDeliveries else { return nil }
		let label = nextMessageLabel()
		let delivery = LabeledDelivery()
		delivery.label = label
		delivery.conversation = conversation
		delivery.state = .pending
		/* The line still has the connection's flood queue ahead of it. Its
		 deadline starts over when the connection writes it. */
		delivery.deadline = .now + LabeledResponsePolicy.queuedTimeout
		labeledResponses.pending[label] = delivery
		scheduleDeliveryDeadlineSweep()
		return label
	}

	/** Starts a labelled line's deadline once the connection writes it.

	 The connection reports each line as flood control releases it, which can be
	 well after it was printed: a long paste goes out a few lines a second. The
	 server's time to answer is counted from here. */
	func noteLabeledLineWritten(_ line: String) {
		guard labeledResponses.pending.isEmpty == false,
		      let label = LabeledResponsePolicy.label(inOutgoingLine: line),
		      let delivery = labeledResponses.pending[label], delivery.resolved == false
		else { return }
		delivery.deadline = .now + LabeledResponsePolicy.timeout
		if let fireDate = labeledResponses.deadlineTaskFireDate, delivery.deadline < fireDate {
			labeledResponses.deadlineTask?.cancel()
			labeledResponses.deadlineTask = nil
			labeledResponses.deadlineTaskFireDate = nil
		}
		scheduleDeliveryDeadlineSweep()
	}

	/** Keeps one task waiting for the earliest pending deadline.

	 One sleeping task per labelled message meant up to 512 of them, each woken
	 to find, almost always, that its delivery had resolved long ago. This one
	 sleeps until the oldest unanswered delivery is due, fails whatever has come
	 due by then, and waits again for the next. Nothing to wait for ends it. */
	private func scheduleDeliveryDeadlineSweep() {
		guard labeledResponses.deadlineTask == nil,
		      let earliest = labeledResponses.pending.values.lazy.map(\.deadline).min()
		else { return }

		labeledResponses.deadlineTaskFireDate = earliest
		labeledResponses.deadlineTask = Task { [weak self] in
			try? await Task.sleep(until: earliest, clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			labeledResponses.deadlineTask = nil
			labeledResponses.deadlineTaskFireDate = nil
			failDeliveries(dueBy: .now)
			scheduleDeliveryDeadlineSweep()
		}
	}

	/// Fails every pending delivery whose deadline is `instant` or earlier.
	func failDeliveries(dueBy instant: ContinuousClock.Instant) {
		let dueLabels = labeledResponses.pending.filter { $0.value.deadline <= instant }.map(\.key)

		for label in dueLabels {
			timeoutDelivery(withLabel: label)
		}
	}

	/** Settles every delivery still waiting as failed, for a connection that has
	 ended.

	 Nothing will answer a label once the session it went out on is gone, and
	 dropping the table left each of those lines drawn as pending for good. */
	func failPendingDeliveriesForDisconnect() {
		labeledResponses.deadlineTask?.cancel()
		labeledResponses.deadlineTask = nil
		labeledResponses.deadlineTaskFireDate = nil
		labeledResponses.timedOut.removeAll()

		for label in Array(labeledResponses.pending.keys) {
			resolveDelivery(
				withLabel: label,
				state: .failed,
				messageIdentifier: nil,
				reason: String(localized: .IRC.miscellaneousMessagesRelatedDisconnected)
			)
		}

		labeledResponses.pending.removeAll()
	}

	func timeoutDelivery(withLabel label: String) {
		guard let delivery = labeledResponses.pending[label], !delivery.resolved else { return }
		resolveDelivery(
			withLabel: label,
			state: .failed,
			messageIdentifier: nil,
			reason: String(localized: .IRC.serverDidNotAcknowledgeThisMessage)
		)
		guard let conversation = delivery.conversation, delivery.lineNumber != nil else { return }
		labeledResponses.timedOut.insert(TimedOutDeliveries.Entry(
			label: label,
			target: IRCCaseFolding.fold(conversation.name, using: supportInfo.caseMapping),
			delivery: delivery
		))
	}

	func resolveDelivery(
		withLabel label: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?,
		echoedMessage: Message? = nil
	) {
		guard let delivery = labeledResponses.pending[label], !delivery.resolved else { return }
		delivery.resolved = true
		delivery.state = state
		/* Without this the table grows by one entry per outgoing message for the
		 whole session, and a server reusing a stale label would keep matching it. */
		labeledResponses.pending.removeValue(forKey: label)
		if labeledResponses.pending.isEmpty {
			labeledResponses.deadlineTask?.cancel()
			labeledResponses.deadlineTask = nil
			labeledResponses.deadlineTaskFireDate = nil
		}
		for batch in batchMessages.queuedEntries.values where batch.labeledDelivery.label == label {
			batch.labeledDelivery.label = nil
		}
		applyDeliveryOutcome(
			to: delivery,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason,
			echoedMessage: echoedMessage
		)
	}

	/// Redraws a delivery's printed line in its settled state, taking the
	/// echo's text and time when the server sent one back.
	private func applyDeliveryOutcome(
		to delivery: LabeledDelivery,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?,
		echoedMessage: Message?
	) {
		guard let lineNumber = delivery.lineNumber else { return }

		if var line = delivery.printedLine {
			line.messageIdentifier = messageIdentifier ?? line.messageIdentifier
			line.deliveryState = state
			if state == .delivered, let echoedMessage, let payload = echoedMessage.params.dropFirst().first {
				let content = InboundTextPolicy.classify(command: echoedMessage.remoteCommand, payload: payload)
				line.messageBody = WireRedaction.redactedServiceMessage(content.text, sentTo: delivery.conversation?.name ?? "")
				line.lineType = LinePresentationPolicy.normalized(content.lineType)
				line.command = echoedMessage.command.lowercased()
				if echoedMessage.hasServerTime {
					line.receivedAt = echoedMessage.receivedAt
					line.serverTimestamp = echoedMessage.receivedAt
				}
			}
			delivery.conversation?.presentation?.replacePendingLine(line, reason: reason)
			return
		}
		delivery.conversation?.presentation?.updateDeliveryState(
			forLineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason
		)
	}

	func resolveLabeledResponse(for message: Message) -> Bool {
		guard isCapabilityEnabled(.labeledResponse) else { return false }

		if message.remoteCommand == .batch {
			return false
		}

		var label = message.messageTags?["label"]
		let batch = message.parentBatchMessage?.labeledResponseBatch
		if label?.isEmpty ?? true {
			label = batch?.labeledDelivery.label
		}
		guard
			let label,
			!label.isEmpty
		else { return false }
		guard let delivery = labeledResponses.pending[label], !delivery.resolved else {
			/* An unknown or already-resolved label must not consume the message: the
			 inbound dispatcher drops anything this reports as handled. Only the
			 late echo of a line that timed out settles that line instead. */
			return settleTimedOutDelivery(echoedBy: message, label: label)
		}

		// Numerics still reach their normal handler after settling the delivery so
		// away messages and server error explanations remain visible.
		let kind = LabeledResponsePolicy.responseKind(command: message.remoteCommand, numeric: message.commandNumeric)
		if let batch, batch.labeledDelivery.label == label {
			switch kind {
			case .failure:
				batch.labeledDelivery.outcome = .failed
				batch.labeledDelivery.failureReason = message.params.last
			case .echo:
				batch.labeledDelivery.messageIdentifier = message.messageIdentifier
				var echo = message
				echo.parentBatchMessage = nil
				batch.labeledDelivery.echoedMessage = echo
			case .acknowledgement:
				break
			case .unrelated:
				return false
			}
			return message.commandNumeric == 0
		}

		switch kind {
		case .failure:
			resolveDelivery(withLabel: label, state: .failed, messageIdentifier: nil, reason: message.params.last)
			return message.commandNumeric == 0
		case .acknowledgement:
			resolveDelivery(withLabel: label, state: .delivered, messageIdentifier: nil, reason: nil)
			return message.commandNumeric == 0
		case .echo:
			resolveDelivery(
				withLabel: label,
				state: .delivered,
				messageIdentifier: message.messageIdentifier,
				reason: nil,
				echoedMessage: message
			)
			return true
		case .unrelated:
			return false
		}
	}

	/** Settles a line drawn as failed when its echo arrives after all.

	 Only an echo from this session, to the conversation the line was printed
	 in, claims a timed-out label; anything else carrying it is handled as if
	 the label were unknown. */
	private func settleTimedOutDelivery(echoedBy message: Message, label: String) -> Bool {
		guard message.parentBatchMessage == nil,
		      LabeledResponsePolicy.responseKind(command: message.remoteCommand, numeric: message.commandNumeric) == .echo,
		      let sender = message.senderNickname, nicknameIsMyself(sender),
		      var target = message.params.first
		else { return false }
		if supportInfo.extractStatusMessagePrefix(fromTargetNamed: target).count == 1 {
			target.removeFirst()
		}
		guard let entry = labeledResponses.timedOut.take(
			label: label,
			target: IRCCaseFolding.fold(target, using: supportInfo.caseMapping)
		) else { return false }
		entry.delivery.state = .delivered
		applyDeliveryOutcome(
			to: entry.delivery,
			state: .delivered,
			messageIdentifier: message.messageIdentifier,
			reason: nil,
			echoedMessage: message
		)
		return true
	}

	/// The state of a delivery still awaiting a response. Resolved deliveries are
	/// removed, so a resolved or unknown label reports `.none`.
	///
	/// For tests: the send path keeps the pending table private, and this is the
	/// only way to observe what it holds.
	func deliveryState(forLabel label: String) -> ChatLineDeliveryState {
		labeledResponses.pending[label]?.state ?? .none
	}
}
