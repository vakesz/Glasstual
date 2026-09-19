// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

// AppKit: one message's attributed text is cut into wire lines here.
import AppKit
import Foundation

private let truncationPRIVMSGCommandConstant = 9
private let truncationACTIONCommandConstant = 17
private let truncationNOTICECommandConstant = 8
private let truncationHostmaskConstant = 60
private let truncationWrapMaxDistance = 25

/// U+200D. A composed character sequence stops at one, so a family or a
/// profession emoji is several sequences that must not be told apart.
private let zeroWidthJoiner: unichar = 0x200D

/** The smallest run at `location` that a line break must not fall inside.

 `rangeOfComposedCharacterSequence(at:)` alone is not that run. It stops at a
 zero-width joiner, so wrapping a line between two of its sequences turned one
 emoji into two or three unrelated ones; and it knows nothing about mIRC codes,
 so a `\u{3}` the person pasted could go out on one line with its digits on the
 next, where they read as text. */
private func unbreakableUnitRange(in string: NSString, at location: Int) -> NSRange {
	let length = string.length
	let character = string.character(at: location)

	if character == TextFormatterControlCharacter.colorDigit ||
		character == TextFormatterControlCharacter.colorHex
	{
		let consumed = string.colorComponents(
			ofCharacter: character,
			startingAt: UInt(location)
		).charactersConsumed

		return NSRange(location: location, length: min(max(consumed, 1), length - location))
	}

	let range = string.rangeOfComposedCharacterSequence(at: location)
	var end = range.location + range.length

	while end < length, string.character(at: end) == zeroWidthJoiner {
		end += 1

		guard end < length else {
			break
		}

		let joined = string.rangeOfComposedCharacterSequence(at: end)
		end = joined.location + joined.length
	}

	return NSRange(location: range.location, length: end - range.location)
}

/// Byte count of `string` on the wire. The 512-byte IRC line limit is a byte
/// budget, so UTF-16 code units must not be counted against it.
private func wireByteCount(_ string: String, encoding: UInt) -> Int {
	let count = (string as NSString).lengthOfBytes(using: encoding)

	return count > 0 ? count : string.utf8.count
}

/** How many bytes of one IRC line are left.

 An IRC line is capped in **bytes**, not characters: 512 including the CR LF,
 or whatever `LINELEN` raises that to. The framing the server prepends — the
 sender's hostmask, the command, the target, the separators — is charged before
 any of the message body is, so what the body actually gets is the difference.

 The arithmetic is signed on purpose. A server-assigned hostmask plus a long
 target name can make the framing alone longer than the whole line, and the
 unsigned subtraction that used to compute the remainder wrapped that case into
 a budget of four billion bytes. Here it simply reads as exhausted. */
nonisolated struct LineBudget: Equatable, Sendable {
	/// What the wire framing costs before the body starts.
	let overhead: Int

	/// The longest line, in bytes, the server accepts.
	let maximum: Int

	/// Bytes charged so far, framing included.
	private(set) var used: Int

	init(overhead: Int, maximum: Int) {
		self.overhead = max(overhead, 0)
		self.maximum = max(maximum, 0)
		used = self.overhead
	}

	/// `true` once nothing more fits — including when the framing alone
	/// already overran the line.
	var isOverBudget: Bool {
		used > maximum
	}

	/// The bytes still available. Never negative.
	var remaining: Int {
		max(maximum - used, 0)
	}

	/// Whether `byteCount` more bytes would still fit.
	func fits(_ byteCount: Int) -> Bool {
		used + max(byteCount, 0) <= maximum
	}

	/// Charges `byteCount` bytes against the line. A negative count is ignored
	/// rather than refunding bytes that were never spent.
	mutating func charge(_ byteCount: Int) {
		used += max(byteCount, 0)
	}
}

extension LineBudget {
	/** The budget for one line of `lineType` addressed to `targetName`.

	 The framing charged up front is what the *server* will prepend when it
	 relays the line: `:hostmask COMMAND target :`, plus the CR LF. The
	 hostmask is only known once the server has told us, so a constant stands
	 in until it has. */
	@MainActor
	static func forMessage(
		toTarget targetName: String,
		on session: ServerSession,
		lineType: ChatLineKind,
		encoding: UInt
	) -> LineBudget {
		var overhead = 1

		if let userHostmask = session.userHostmask {
			overhead += wireByteCount(userHostmask, encoding: encoding)
		} else {
			overhead += truncationHostmaskConstant
		}

		switch lineType {
		case .privateMessage, .privateMessageNoHighlight:
			overhead += truncationPRIVMSGCommandConstant
		case .action, .actionNoHighlight:
			overhead += truncationACTIONCommandConstant
		case .notice:
			overhead += truncationNOTICECommandConstant
		default:
			preconditionFailure("Line type not supported")
		}

		overhead += wireByteCount(targetName, encoding: encoding)
		overhead += 2
		overhead += 2

		var maximum = 510
		let serverLineLength = Int(session.supportInfo.maximumLineLength)

		if serverLineLength > (overhead + 2) {
			maximum = serverLineLength - 2
		}

		return LineBudget(overhead: overhead, maximum: maximum)
	}
}

/** One message's text, consumed one wire line at a time.

 A message longer than the line budget goes out as several lines, and each of
 them is cut from the front of what is left. The cursor is a value that hands
 back the remainder, so no mutable AppKit object sits in the send path. */
@MainActor
struct LineCursor {
	private var remaining: NSAttributedString

	init(_ text: NSAttributedString) {
		remaining = text
	}

	/// How much of the text is still to be sent. Each line consumes a prefix,
	/// so this only ever falls, and reaching zero is what ends the message.
	/// For tests: they watch it fall to prove every pass makes progress.
	var length: Int {
		remaining.length
	}

	/// For tests: the send loop ends on `nextLine` answering `nil`, so nothing in
	/// the app asks this — a test does, to say the cursor was fully consumed.
	var isEmpty: Bool {
		length == 0
	}

	/** The next wire line, or `nil` once there is nothing left to send.

	 `nil` also answers the case a caller would otherwise have to guard by hand:
	 formatting that consumed nothing loops forever, so a pass that makes no
	 progress ends the message instead. */
	mutating func nextLine(
		forTarget targetName: String,
		on session: ServerSession,
		with lineType: ChatLineKind
	) -> String? {
		guard remaining.length > 0 else {
			return nil
		}

		var consumed = NSRange()
		let line = remaining.stringFormatted(
			forTarget: targetName,
			on: session,
			with: lineType,
			effectiveRange: &consumed
		)

		let end = consumed.location + consumed.length

		guard consumed.location == 0, end > 0, end <= remaining.length else {
			return nil
		}

		remaining = remaining.attributedSubstring(
			from: NSRange(location: end, length: remaining.length - end)
		)

		return line
	}
}

extension NSAttributedString {
	func stringFormatted(
		forTarget targetName: String,
		on session: ServerSession,
		with lineType: ChatLineKind,
		effectiveRange: NSRangePointer?
	) -> String {
		let encoding = session.effectivePrimaryEncoding
		var budget = LineBudget.forMessage(
			toTarget: targetName,
			on: session,
			lineType: lineType,
			encoding: encoding.rawValue
		)

		let string = string as NSString
		var result = ""

		var deletionLength: UInt = 0
		var consumedAnyCharacter = false
		var limitRange = NSRange(location: 0, length: string.length)

		while limitRange.length > 0 {
			var breakLoopAfterAppend = false
			var segmentRange = NSRange()

			let attributes = attributes(
				at: limitRange.location,
				longestEffectiveRange: &segmentRange,
				in: limitRange
			)
			let formatters = TextFormatterEffects(attributes: attributes)
			let formattersLength = formatters.maximumLength

			if segmentRange.location > 0, budget.fits(Int(formattersLength) + 2) == false {
				break
			}

			budget.charge(Int(formattersLength))
			formatters.appendToStart(of: &result)

			/* Where this segment's own characters start in `result`.

			 `deletionLength` counts UTF-16 units of the plain source; `result`
			 also holds the control codes the formatters injected, so the two
			 run at different offsets. Everything appended from here to the end
			 of the segment is copied from the source verbatim, which is what
			 lets a wrap inside this window be measured in either. */
			let segmentResultLocation = result.utf16.count

			var i = 0

			while i < segmentRange.length {
				let characterIndex = segmentRange.location + i
				let characterRange = unbreakableUnitRange(in: string, at: characterIndex)
				let character = string.substring(with: characterRange)
				var characterSize = (character as NSString).lengthOfBytes(using: encoding.rawValue)

				if characterSize == 0 {
					characterSize = characterRange.length
				}

				budget.charge(characterSize)

				if budget.isOverBudget {
					if consumedAnyCharacter {
						/* The floor is in `result`'s coordinates, so the wrap
						 cannot back past this segment's first character. Held
						 there, the units it removed from `result` are exactly
						 the source units it gave back — and `deletionLength` is
						 the ceiling on how many it may remove, because a unit
						 taken off `result` that is not given back here is a
						 character the caller believes it sent and never will.
						 The wrap declines rather than truncate past it. */
						let indexDifference = result.wrapIRCTextFormatterResult(
							with: UInt(segmentResultLocation),
							maxDistance: UInt(truncationWrapMaxDistance),
							maximumGiveBack: deletionLength
						)

						if indexDifference != UInt(bitPattern: NSNotFound) {
							deletionLength -= indexDifference
						}
					} else {
						// A server-assigned hostmask plus a long target name
						// can push the minimum length past the maximum. Consume
						// the character anyway: the callers loop until the
						// string is empty, and consuming nothing never ends.
						deletionLength += UInt(characterRange.length)
						result.append(character)
					}

					breakLoopAfterAppend = true

					break
				}

				consumedAnyCharacter = true
				deletionLength += UInt(characterRange.length)
				i += characterRange.length
				result.append(character)
			}

			formatters.appendToEnd(of: &result)

			if breakLoopAfterAppend {
				break
			}

			let segmentRangeNewLength = string.length - Int(deletionLength)

			if segmentRangeNewLength <= 0 {
				break
			}

			limitRange = NSRange(location: Int(deletionLength), length: segmentRangeNewLength)
		}

		if let effectiveRange {
			effectiveRange.pointee = NSRange(location: 0, length: Int(deletionLength))
		}

		return result
	}
}

nonisolated extension String { // nonisolated: pure
	/** Breaks the tail of a formatted line at a space rather than mid-word.

	 Truncates this string back to the last space within `maxDistance` UTF-16
	 units of its end and answers how many units went; `NSNotFound` when there is
	 no space to break at, in which case the string is left alone.

	 `maximumGiveBack` is how many units the caller can hand back to the queue.
	 Truncating more than that drops text: the characters leave the line being
	 sent while the caller still counts them as consumed, so nothing ever sends
	 them. Past that ceiling the wrap declines and the line goes out unwrapped,
	 which re-queues the tail instead of losing it. */
	mutating func wrapIRCTextFormatterResult(
		with minimumIndex: UInt,
		maxDistance: UInt,
		maximumGiveBack: UInt = .max
	) -> UInt {
		let text = self as NSString
		let selfLength = text.length
		let distance = Int(clamping: maxDistance)

		// The window is the tail of the string. Computing its start in
		// unsigned arithmetic underflowed whenever the result was shorter
		// than the distance, producing a large-negative NSRange location and
		// an uncatchable NSRangeException.
		guard distance > 0, selfLength > 0 else {
			return UInt(bitPattern: NSNotFound)
		}

		let searchStart = max(0, selfLength - 1 - distance)
		let searchLength = min(distance, selfLength - searchStart)

		guard searchLength > 0 else {
			return UInt(bitPattern: NSNotFound)
		}

		let searchRange = NSRange(location: searchStart, length: searchLength)
		let spaceRange = text.rangeOfCharacter(
			from: .whitespaces,
			options: .backwards,
			range: searchRange
		)

		if spaceRange.location == NSNotFound || spaceRange.location < Int(minimumIndex) {
			return UInt(bitPattern: NSNotFound)
		}

		let indexDifference = selfLength - spaceRange.location

		guard UInt(indexDifference) <= maximumGiveBack else {
			return UInt(bitPattern: NSNotFound)
		}

		self = text.substring(to: spaceRange.location)

		return UInt(indexDifference)
	}
}
