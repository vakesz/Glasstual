// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Messages this session sent without printing them, so that their echo is not
 printed either.

 `/smsg`, `/sme`, a connect command run silently and the identification the
 session sends services on its own are kept out of the transcript on purpose.
 With `echo-message` the server sends each of them back. Where
 `labeled-response` is on, each goes out with a label and its echo is matched
 by that label; otherwise the only way to know it is one of these is what it
 says and where it went.

 An entry waits as long as its line waits in the connection's flood queue, and
 lapses ``lifetime`` after the connection writes it. No entry still waiting is
 dropped to make room: a full registry refuses the next one instead, so the
 caller can hold that line back rather than let its echo print. */
struct UnprintedEchoRegistry {
	/// The most entries waiting at once, written or not. A server that never
	/// echoes holds at most this many, each for ``lifetime`` after its write.
	static let capacity = 512
	static let lifetime: Duration = .seconds(60)

	private struct Entry {
		let target: String
		let text: String
		let lineType: ChatLineKind
		/// The `label` tag the line went out with, if any.
		let label: String?
		/// When the entry lapses; nil while the line has not been written.
		var expiry: ContinuousClock.Instant?
	}

	private var entries: [Entry] = []

	/// Whether nothing is waiting for its echo.
	var isEmpty: Bool {
		entries.isEmpty
	}

	/** Notes a message sent to `target`, without any STATUSMSG prefix, before
	 it is handed to the connection.

	 Returns false, recording nothing, when ``capacity`` entries are still
	 waiting: the caller should not send the line. */
	@discardableResult
	mutating func record(
		target: String,
		text: String,
		lineType: ChatLineKind,
		label: String? = nil,
		caseMapping: ISupportCaseMapping,
		now: ContinuousClock.Instant = .now
	) -> Bool {
		prune(now: now)
		guard entries.count < Self.capacity else { return false }
		entries.append(Entry(
			target: IRCCaseFolding.fold(target, using: caseMapping),
			text: text,
			lineType: lineType,
			label: label,
			expiry: nil
		))
		return true
	}

	/// Starts the lifetime of the entry sent with `label`, as the connection writes it.
	mutating func noteWritten(label: String, now: ContinuousClock.Instant = .now) {
		guard let index = entries.firstIndex(where: { $0.label == label && $0.expiry == nil }) else { return }
		entries[index].expiry = now + Self.lifetime
	}

	/// Starts the lifetime of the oldest unwritten, unlabelled entry the written line matches.
	mutating func noteWritten(
		target: String,
		text: String,
		lineType: ChatLineKind,
		caseMapping: ISupportCaseMapping,
		now: ContinuousClock.Instant = .now
	) {
		let folded = IRCCaseFolding.fold(target, using: caseMapping)
		guard let index = entries.firstIndex(where: {
			$0.expiry == nil && $0.label == nil && $0.target == folded && $0.text == text && $0.lineType == lineType
		}) else { return }
		entries[index].expiry = now + Self.lifetime
	}

	/// Whether an echo carries the label of a recorded message, which it then uses up.
	mutating func consume(label: String, now: ContinuousClock.Instant = .now) -> Bool {
		prune(now: now)
		guard let index = entries.firstIndex(where: { $0.label == label }) else { return false }
		entries.remove(at: index)
		return true
	}

	/// Whether an echo matches a recorded message, which it then uses up.
	mutating func consume(
		target: String,
		text: String,
		lineType: ChatLineKind,
		caseMapping: ISupportCaseMapping,
		now: ContinuousClock.Instant = .now
	) -> Bool {
		prune(now: now)
		let folded = IRCCaseFolding.fold(target, using: caseMapping)
		guard let index = entries.firstIndex(where: {
			$0.target == folded && $0.text == text && $0.lineType == lineType
		}) else { return false }
		entries.remove(at: index)
		return true
	}

	mutating func removeAll() {
		entries.removeAll()
	}

	private mutating func prune(now: ContinuousClock.Instant) {
		entries.removeAll { $0.expiry.map { $0 <= now } ?? false }
	}
}

extension ServerSession {
	/** Notes a message that is not printed locally, while its echo would be,
	 and returns the tags to send it with: a label where labelled responses
	 are tracked, and nothing otherwise. No tag marks the message as unprinted,
	 because a client tag is relayed to the recipient and would tell them which
	 client sent it and that no copy was kept.

	 Returns nil when the message must not go out: too many earlier ones are
	 still waiting for their echo, and this one's would print. */
	func noteUnprintedSend(to target: String, text: String, lineType: ChatLineKind) -> [String: String]? {
		var tags: [String: String] = [:]
		guard isCapabilityEnabled(.echoMessage) else { return tags }
		let label = labeledResponseTrackingEnabled() ? nextMessageLabel() : nil
		guard unprintedEchoes.record(
			target: target,
			text: text,
			lineType: lineType,
			label: label,
			caseMapping: supportInfo.caseMapping
		) else { return nil }
		tags["label"] = label
		return tags
	}

	/** Sends the identification text services asked for without printing it.
	 When too many unprinted lines are waiting to track this one too, it still
	 goes out: services are waiting on it, and its echo, like any message to a
	 service, has its credentials masked. */
	func sendUnprinted(_ command: RemoteCommand, to target: String, text: String) {
		let tags = noteUnprintedSend(to: target, text: text, lineType: .privateMessage) ?? [:]
		sendCommand(command, arguments: [target, text], tags: tags)
	}

	/** Starts the lifetime of the unprinted message `line` carries, now that the
	 connection writes it. A long paste can wait in flood control for longer
	 than an entry lives, so the time is counted from here, not from when the
	 line was produced. */
	func noteUnprintedLineWritten(_ line: String) {
		guard unprintedEchoes.isEmpty == false else { return }
		if let label = LabeledResponsePolicy.label(inOutgoingLine: line) {
			unprintedEchoes.noteWritten(label: label)
			return
		}
		guard let message = Message(line: line),
		      message.remoteCommand == .privmsg || message.remoteCommand == .notice,
		      message.params.count > 1
		else { return }
		var target = message.params[0]
		if supportInfo.extractStatusMessagePrefix(fromTargetNamed: target).count == 1 {
			target.removeFirst()
		}
		let content = InboundTextPolicy.classify(command: message.remoteCommand, payload: message.params[1])
		unprintedEchoes.noteWritten(
			target: target,
			text: content.text,
			lineType: content.lineType,
			caseMapping: supportInfo.caseMapping
		)
	}

	/** Whether `message` is the echo of a message sent without a local print.

	 Only a live echo is matched: by its label, which the server puts on the
	 echo or on the batch around it, and failing that by what it says and where
	 it went. A copy a bouncer or `chathistory` plays back later carries nothing
	 to recognise it by and is printed; one sent to a service still has its
	 credentials masked. */
	func consumeUnprintedEcho(_ message: Message, target: String, text: String, lineType: ChatLineKind) -> Bool {
		let label = message.messageTags?["label"] ?? message.parentBatchMessage?.openingMessage?.messageTags?["label"]
		let consume = {
			if let label, self.unprintedEchoes.consume(label: label) {
				return true
			}
			return self.unprintedEchoes.consume(
				target: target,
				text: text,
				lineType: lineType,
				caseMapping: self.supportInfo.caseMapping
			)
		}
		guard message.isReplayed == false, isCapabilityEnabled(.echoMessage), unprintedEchoes.isEmpty == false else {
			return false
		}
		return consume()
	}
}
