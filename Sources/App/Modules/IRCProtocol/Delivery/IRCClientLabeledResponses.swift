/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
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

import Foundation

enum IRCLabeledResponsePolicy {
	static let timeoutInterval: TimeInterval = 30

	static func responseKind(command: String, commandNumeric: UInt) -> ResponseKind {
		if command.caseInsensitiveCompare("FAIL") == .orderedSame {
			return .failure
		}
		if command.caseInsensitiveCompare("ACK") == .orderedSame {
			return .acknowledgement
		}
		if command.caseInsensitiveCompare("PRIVMSG") == .orderedSame ||
			command.caseInsensitiveCompare("NOTICE") == .orderedSame ||
			command.caseInsensitiveCompare("TAGMSG") == .orderedSame ||
			commandNumeric == IRCRemoteCommand.privmsg.rawValue ||
			commandNumeric == IRCRemoteCommand.notice.rawValue ||
			commandNumeric == IRCRemoteCommand.tagmsg.rawValue
		{
			return .echo
		}
		return .unrelated
	}

	enum ResponseKind {
		case failure
		case acknowledgement
		case echo
		case unrelated
	}
}

@objc(IRCLabeledDelivery)
final class LabeledDelivery: NSObject, @unchecked Sendable {
	@objc var label = ""
	@objc weak var channel: IRCChannel?
	@objc var lineNumber: String?
	@objc var resolved = false
	@objc var state: TVCLogLineDeliveryState = .none
	var timeoutWorkItem: DispatchWorkItem?
}

public extension IRCClient {
	@objc(labeledResponseTrackingEnabled)
	func labeledResponseTrackingEnabled() -> Bool {
		isCapabilityEnabled(.labeledResponse) && isCapabilityEnabled(.echoMessage)
	}

	@objc(nextMessageLabel)
	func nextMessageLabel() -> String {
		labelCounter += 1
		return "g\(labelCounter)"
	}

	@objc(registerPendingDeliveryForChannel:)
	func registerPendingDelivery(for channel: IRCChannel?) -> String? {
		guard labeledResponseTrackingEnabled() else { return nil }
		let label = nextMessageLabel()
		let delivery = LabeledDelivery()
		delivery.label = label
		delivery.channel = channel
		delivery.state = .pending

		let timeout = DispatchWorkItem { [weak self] in
			Task { @MainActor in self?.timeoutDelivery(withLabel: label) }
		}
		delivery.timeoutWorkItem = timeout
		pendingDeliveries[label] = delivery
		DispatchQueue.main.asyncAfter(deadline: .now() + IRCLabeledResponsePolicy.timeoutInterval, execute: timeout)
		return label
	}

	@objc(attachLineNumber:toDeliveryWithLabel:)
	func attachLineNumber(_ lineNumber: String, toDeliveryWithLabel label: String) {
		nativeDelivery(pendingDeliveries[label])?.lineNumber = lineNumber
	}

	@objc(timeoutDeliveryWithLabel:)
	func timeoutDelivery(withLabel label: String) {
		guard let delivery = nativeDelivery(pendingDeliveries[label]), !delivery.resolved else { return }
		resolveDelivery(
			withLabel: label,
			state: .failed,
			messageIdentifier: nil,
			reason: IRCConnectionStrings.labeledResponseNotAcknowledged
		)
	}

	@objc(resolveDeliveryWithLabel:state:messageIdentifier:reason:)
	func resolveDelivery(
		withLabel label: String,
		state: TVCLogLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	) {
		guard let delivery = nativeDelivery(pendingDeliveries[label]), !delivery.resolved else { return }
		delivery.resolved = true
		delivery.state = state
		delivery.timeoutWorkItem?.cancel()
		delivery.timeoutWorkItem = nil
		/* Without this the table grows by one entry per outgoing message for the
		 whole session, and a server reusing a stale label would keep matching it. */
		pendingDeliveries.removeObject(forKey: label)
		guard let lineNumber = delivery.lineNumber else { return }

		let arguments: [Any] = [
			lineNumber,
			LogLine.string(for: state) ?? "",
			messageIdentifier ?? NSNull(),
			reason ?? NSNull(),
		]
		delivery.channel?.viewController?.evaluateFunction(
			"_Glasstual.lineDeliveryStateChanged",
			withArguments: arguments
		)
	}

	@objc(resolveLabeledResponseForMessage:)
	func resolveLabeledResponse(for message: Message) -> Bool {
		resolveLabeledResponseOnMainActor(message)
	}

	/// The state of a delivery still awaiting a response. Resolved deliveries are
	/// removed, so a resolved or unknown label reports `.none`.
	@objc(deliveryStateForLabel:)
	func deliveryState(forLabel label: String) -> TVCLogLineDeliveryState {
		nativeDelivery(pendingDeliveries[label])?.state ?? .none
	}
}

private extension IRCClient {
	@MainActor
	func resolveLabeledResponseOnMainActor(_ message: Message) -> Bool {
		guard isCapabilityEnabled(.labeledResponse) else { return false }
		let command = message.command

		if command.caseInsensitiveCompare("BATCH") == .orderedSame {
			resolveLabeledBatchBoundary(message)
			return false
		}

		var label = message.messageTags?["label"]
		if label?.isEmpty ?? true, let batchToken = message.batchToken, !batchToken.isEmpty {
			label = labelForBatchToken.object(forKey: batchToken) as? String
		}
		guard
			let label,
			!label.isEmpty,
			let delivery = nativeDelivery(pendingDeliveries[label]),
			!delivery.resolved
		else {
			/* An unknown or already-resolved label must not consume the message: the
			 inbound dispatcher drops anything this reports as handled. */
			return false
		}

		switch IRCLabeledResponsePolicy.responseKind(command: command, commandNumeric: message.commandNumeric) {
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

	@MainActor
	func resolveLabeledBatchBoundary(_ message: Message) {
		guard let reference = message.params.first else { return }
		if reference.hasPrefix("+"), let label = message.messageTags?["label"], !label.isEmpty {
			labelForBatchToken[String(reference.dropFirst())] = label
		} else if reference.hasPrefix("-") {
			let token = String(reference.dropFirst())
			if let label = labelForBatchToken.object(forKey: token) as? String {
				labelForBatchToken.removeObject(forKey: token)
				resolveDelivery(withLabel: label, state: .delivered, messageIdentifier: nil, reason: nil)
			}
		}
	}

	func nativeDelivery(_ delivery: Any?) -> LabeledDelivery? {
		delivery as? LabeledDelivery
	}
}
