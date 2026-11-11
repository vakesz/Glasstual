// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Messages this session sent without printing them, so that their echo is not
 printed either.

 `/smsg`, `/sme`, a connect command run silently and the identification the
 session sends services on its own are kept out of the transcript on purpose.
 With `echo-message` the server sends each of them back, and nothing labels the
 echo, so the only way to know it is one of these is what it says and where it
 went. An entry matches one echo and lapses after ``lifetime``; the oldest goes
 once ``capacity`` are waiting. */
struct UnprintedEchoRegistry {
	static let capacity = 32
	static let lifetime: Duration = .seconds(60)

	private struct Entry {
		let target: String
		let text: String
		let lineType: ChatLineKind
		let expiry: ContinuousClock.Instant
	}

	private var entries: [Entry] = []

	/// Whether nothing is waiting for its echo.
	var isEmpty: Bool {
		entries.isEmpty
	}

	/// Notes a message sent to `target`, without any STATUSMSG prefix.
	mutating func record(
		target: String,
		text: String,
		lineType: ChatLineKind,
		caseMapping: ISupportCaseMapping,
		now: ContinuousClock.Instant = .now
	) {
		prune(now: now)
		if entries.count >= Self.capacity {
			entries.removeFirst(entries.count - Self.capacity + 1)
		}
		entries.append(Entry(
			target: IRCCaseFolding.fold(target, using: caseMapping),
			text: text,
			lineType: lineType,
			expiry: now + Self.lifetime
		))
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
		entries.removeAll { $0.expiry <= now }
	}
}

extension ServerSession {
	/// Notes a message that is not printed locally, while its echo would be.
	func noteUnprintedSend(to target: String, text: String, lineType: ChatLineKind) {
		guard isCapabilityEnabled(.echoMessage) else { return }
		unprintedEchoes.record(target: target, text: text, lineType: lineType, caseMapping: supportInfo.caseMapping)
	}

	/// Whether `message` is the echo of a message sent without a local print.
	func consumeUnprintedEcho(_ message: Message, target: String, text: String, lineType: ChatLineKind) -> Bool {
		guard message.isReplayed == false, isCapabilityEnabled(.echoMessage), unprintedEchoes.isEmpty == false else {
			return false
		}
		return unprintedEchoes.consume(target: target, text: text, lineType: lineType, caseMapping: supportInfo.caseMapping)
	}
}
