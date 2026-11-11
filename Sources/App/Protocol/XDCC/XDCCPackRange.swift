// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Why a list of pack numbers was refused.
nonisolated enum XDCCPackRangeError: Error, Equatable, Sendable {
	case empty
	/// A part that is not a number or a range of them.
	case malformed(String)
	/// A range that runs backwards, such as `5-1`.
	case reversed(Int, Int)
	/// A number outside ``XDCCAnnouncementParser/packRange``, such as zero.
	case outOfRange(Int)
	/// More packs than one request may ask for.
	case tooMany(limit: Int)
}

/** Expands a list of pack numbers the way a person writes one: `1-5,7,#9`.

 Each part is a number or an inclusive range, optionally prefixed with `#`,
 separated by commas or spaces. Numbers are ASCII digits. Duplicates are
 dropped and the first-written order kept. Expansion stops at the first pack
 past the limit, so `1-999999` costs no more than the limit does. */
nonisolated enum XDCCPackRange {
	static func expand(_ text: String, limit: Int) -> Result<[Int], XDCCPackRangeError> {
		let parts = text.split { $0 == "," || $0.isWhitespace }
		guard parts.isEmpty == false else { return .failure(.empty) }

		var ranges: [ClosedRange<Int>] = []
		for part in parts {
			switch range(String(part)) {
			case let .success(range): ranges.append(range)
			case let .failure(error): return .failure(error)
			}
		}

		var seen = Set<Int>()
		var packs: [Int] = []
		for range in ranges {
			for pack in range where seen.insert(pack).inserted {
				guard packs.count < limit else { return .failure(.tooMany(limit: limit)) }
				packs.append(pack)
			}
		}
		return .success(packs)
	}

	private static func range(_ part: String) -> Result<ClosedRange<Int>, XDCCPackRangeError> {
		let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
		guard bounds.count == 1 || bounds.count == 2 else { return .failure(.malformed(part)) }

		var numbers: [Int] = []
		for bound in bounds {
			let digits = bound.hasPrefix("#") ? bound.dropFirst() : bound
			guard digits.isEmpty == false, digits.count <= 7, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
			      let number = Int(digits)
			else { return .failure(.malformed(part)) }
			guard XDCCAnnouncementParser.packRange.contains(number) else { return .failure(.outOfRange(number)) }
			numbers.append(number)
		}

		guard let lower = numbers.first, let upper = numbers.last else { return .failure(.malformed(part)) }
		guard lower <= upper else { return .failure(.reversed(lower, upper)) }
		return .success(lower ... upper)
	}
}
