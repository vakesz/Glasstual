// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The messages whose labelled answer has not arrived yet.

 IRCv3 `labeled-response` correlates a reply with the line that caused it, so
 the session hands out labels and keeps what each one is waiting for until the
 answer lands or its deadline passes. */
struct LabeledResponseRegistry {
	/// What each outstanding label is waiting for.
	var pending: [String: LabeledDelivery] = [:]
	/// Waits for the earliest deadline in ``pending``; `nil` while nothing is.
	var deadlineTask: Task<Void, Never>?
	/// Where the next label's number comes from.
	var counter: UInt = 0
}

enum LabeledResponsePolicy {
	static let timeout: Duration = .seconds(30)
	static let maximumPendingDeliveries = 512

	/** How a labelled response answers the command that carried the label.

	 The verb is all there is to go on. A numeric carries no `RemoteCommand`
	 at all, so it answers `.unrelated` with the rest of what this does not
	 recognise. */
	static func responseKind(command: RemoteCommand?) -> ResponseKind {
		switch command {
		case .fail: .failure
		case .ack: .acknowledgement
		case .privmsg, .notice, .tagmsg: .echo
		default: .unrelated
		}
	}

	enum ResponseKind {
		case failure
		case acknowledgement
		case echo
		case unrelated
	}
}

/** What a labelled command's answers have said so far, kept on the batch that
 carries the label.

 A batch is the wire's unit of "these lines belong together"; the label, the
 state and the identifier are this subsystem's reading of it, which is why they
 travel as one value it declares rather than as four fields the batch model
 happens to hold. */
struct BatchDeliveryState {
	/// The label this batch answers, or `nil` when it carries none. It is
	/// cleared once the delivery has been resolved.
	var label: String?
	var state: ChatLineDeliveryState = .delivered
	var messageIdentifier: String?
	var failureReason: String?
}

final class LabeledDelivery {
	var label = ""
	weak var conversation: Conversation?
	var lineNumber: String?
	var resolved = false
	var state: ChatLineDeliveryState = .none
	/// When the delivery fails if nothing has answered its label.
	var deadline: ContinuousClock.Instant = .now
}

extension ServerSession {
	/// Whether an outgoing command can be labelled and its answer correlated.
	///
	/// IRCv3 `labeled-response` needs `message-tags` to carry the label, and
	/// nothing else: when the server has no other response it MUST send `ACK`,
	/// which resolves the delivery on its own. Requiring `echo-message` as
	/// well meant a server offering labelled responses without echo had every
	/// message go out untracked.
	func labeledResponseTrackingEnabled() -> Bool {
		isCapabilityEnabled(.labeledResponse) && isCapabilityEnabled(.messageTags)
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
		delivery.deadline = .now + LabeledResponsePolicy.timeout
		labeledResponses.pending[label] = delivery
		scheduleDeliveryDeadlineSweep()
		return label
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

		labeledResponses.deadlineTask = Task { [weak self] in
			try? await Task.sleep(until: earliest, clock: .continuous)

			guard Task.isCancelled == false, let self else { return }

			labeledResponses.deadlineTask = nil
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

	func attachLineNumber(_ lineNumber: String, toDeliveryWithLabel label: String) {
		labeledResponses.pending[label]?.lineNumber = lineNumber
	}

	func timeoutDelivery(withLabel label: String) {
		guard let delivery = labeledResponses.pending[label], !delivery.resolved else { return }
		resolveDelivery(
			withLabel: label,
			state: .failed,
			messageIdentifier: nil,
			reason: String(localized: .IRC.serverDidNotAcknowledgeThisMessage)
		)
	}

	func resolveDelivery(
		withLabel label: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
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
		}
		for batch in batchMessages.queuedEntries.values where batch.labeledDelivery.label == label {
			batch.labeledDelivery.label = nil
		}
		guard let lineNumber = delivery.lineNumber else { return }

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
			!label.isEmpty,
			let delivery = labeledResponses.pending[label],
			!delivery.resolved
		else {
			/* An unknown or already-resolved label must not consume the message: the
			 inbound dispatcher drops anything this reports as handled. */
			return false
		}

		let kind = LabeledResponsePolicy.responseKind(command: message.remoteCommand)
		if let batch, batch.labeledDelivery.label == label {
			switch kind {
			case .failure:
				batch.labeledDelivery.state = .failed
				batch.labeledDelivery.failureReason = message.params.last
			case .echo:
				batch.labeledDelivery.messageIdentifier = message.messageIdentifier
			case .acknowledgement:
				break
			case .unrelated:
				return false
			}
			return true
		}

		switch kind {
		case .failure:
			resolveDelivery(withLabel: label, state: .failed, messageIdentifier: nil, reason: message.params.last)
			return true
		case .acknowledgement:
			resolveDelivery(withLabel: label, state: .delivered, messageIdentifier: nil, reason: nil)
			return true
		case .echo:
			resolveDelivery(
				withLabel: label,
				state: .delivered,
				messageIdentifier: message.messageIdentifier,
				reason: nil
			)
			return true
		case .unrelated:
			return false
		}
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
