/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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
import os
import Synchronization

public enum RegularExpression {
	private struct CacheKey: Hashable {
		let pattern: String
		let caseless: Bool
	}

	/** One compiled pattern.

	 `NSRegularExpression` is declared `NS_SWIFT_SENDABLE` by Foundation and is
	 immutable once built, so the cache below is a value whose every member is
	 `Sendable` — which is what the `Mutex` guarding it asks for. The wrapper
	 gives that fact a name and a place to say it; it is not what makes it
	 true. */
	private struct CompiledExpression: Sendable {
		let expression: NSRegularExpression
	}

	/** Everything the cache remembers about a pattern.

	 A pattern that fails to compile is remembered too. Patterns come from chat
	 filters and from plugin output-suppression rules, and are tried once per
	 incoming message, so a broken one used to be recompiled — and re-logged —
	 for every line that arrived. Recording the failure makes the second attempt as cheap as a hit
	 and keeps the log to one line per distinct pattern. */
	private struct ExpressionCache {
		var compiled: [CacheKey: CompiledExpression] = [:]
		var failed: Set<CacheKey> = []
		/// How many times each pattern has been handed to `NSRegularExpression`.
		/// The whole point of the cache is that this stops at one, and nothing
		/// else observes it: a remembered failure and a fresh one answer a
		/// caller identically.
		var compilations: [CacheKey: Int] = [:]
	}

	private static let logger = Logger(
		subsystem: "com.codeux.frameworks.CocoaExtensions",
		category: "RegularExpression"
	)

	/** Patterns here come from chat filters and plugin output-suppression rules,
	 and are evaluated once per incoming message. Compiling is the
	 expensive part, so hold on to the result; `NSRegularExpression` is
	 immutable and safe to match on from several threads. */
	private static let expressionCache = Mutex(ExpressionCache())

	/// Beyond this the cache is emptied rather than grown. Real use has a few
	/// dozen distinct patterns; a much larger number means something is
	/// generating them, not reusing them.
	private static let expressionCacheLimit = 512

	/** The longest input the bounded entry points hand to ICU.

	 ICU matches by backtracking and has no budget of its own, so the cost of a
	 badly shaped pattern grows with the subject as well as with the pattern.
	 The subjects here are remote: a chat filter is matched against whatever a
	 peer sends. An IRC line is 512 bytes, and even a
	 tagged or multiline one stays far below this, so the cap only ever bites on
	 something that is not a chat message. */
	public static let inputLengthLimit = 4096

	/** How many times this pattern has been handed to `NSRegularExpression`.

	 One is what a pattern costs however often it is used, a pattern that cannot
	 compile included — which is otherwise unobservable, because a remembered
	 failure answers a caller exactly as a fresh one does. Scoped to the pattern
	 so that what anything else in the process compiles does not enter into it.
	 It resets with the cache it counts. */
	public static func compilationCount(of pattern: String, caseless: Bool = false) -> Int {
		expressionCache.withLock { $0.compilations[CacheKey(pattern: pattern, caseless: caseless)] ?? 0 }
	}

	/// `haystack` cut to at most `limit` characters, so a caller can bound the
	/// work a user-authored pattern is allowed to do on remote input.
	public static func boundedInput(_ haystack: String, limit: Int = inputLengthLimit) -> String {
		guard limit >= 0 else { return "" }
		guard haystack.count > limit else { return haystack }
		return String(haystack.prefix(limit))
	}

	public static func string(_ haystack: String, isMatchedByRegex needle: String) -> Bool {
		string(haystack, isMatchedByRegex: needle, withoutCase: false)
	}

	public static func string(_ haystack: String, isMatchedByRegex needle: String, withoutCase caseless: Bool) -> Bool {
		makeExpression(needle, caseless: caseless)?.firstMatch(in: haystack, range: haystack.fullRange) != nil
	}

	/// The same test with the subject cut to `inputLimit` characters first.
	/// Callers matching a user-authored pattern against remote text use this.
	public static func string(
		_ haystack: String,
		isMatchedByRegex needle: String,
		withoutCase caseless: Bool,
		inputLimit: Int
	) -> Bool {
		string(boundedInput(haystack, limit: inputLimit), isMatchedByRegex: needle, withoutCase: caseless)
	}

	public static func string(_ haystack: String, rangeOfRegex needle: String) -> NSRange {
		string(haystack, rangeOfRegex: needle, withoutCase: false)
	}

	public static func string(_ haystack: String, rangeOfRegex needle: String, withoutCase caseless: Bool) -> NSRange {
		makeExpression(needle, caseless: caseless)?.rangeOfFirstMatch(in: haystack, range: haystack.fullRange)
			?? NSRange(location: NSNotFound, length: 0)
	}

	public static func string(_ haystack: String, replacedByRegex needle: String, with replacement: String) -> String {
		makeExpression(needle)?.stringByReplacingMatches(
			in: haystack,
			range: haystack.fullRange,
			withTemplate: replacement
		)
			?? haystack
	}

	public static func matches(
		in haystack: String,
		withRegex needle: String,
		withoutCase caseless: Bool,
		substringGroups: Bool
	) -> [String] {
		matches(
			in: haystack,
			withRegex: needle,
			withoutCase: caseless,
			substringGroups: substringGroups,
			inputLimit: nil
		)
	}

	/// The same enumeration with the subject cut to `inputLimit` characters
	/// first; `nil` leaves the subject alone.
	public static func matches(
		in haystack: String,
		withRegex needle: String,
		withoutCase caseless: Bool,
		substringGroups: Bool,
		inputLimit: Int?
	) -> [String] {
		let subject = inputLimit.map { boundedInput(haystack, limit: $0) } ?? haystack
		guard let expression = makeExpression(needle, caseless: caseless) else { return [] }

		return expression.matches(in: subject, range: subject.fullRange).flatMap { result in
			let ranges = substringGroups ? (0 ..< result.numberOfRanges) : (0 ..< 1)
			return ranges.compactMap { index -> String? in
				let range = result.range(at: index)
				guard range.location != NSNotFound, let swiftRange = Range(range, in: subject) else { return nil }
				return String(subject[swiftRange])
			}
		}
	}

	private static func makeExpression(_ pattern: String, caseless: Bool = false) -> NSRegularExpression? {
		let key = CacheKey(pattern: pattern, caseless: caseless)

		let remembered = expressionCache.withLock { cache -> CompiledExpression?? in
			if let cached = cache.compiled[key] {
				return .some(.some(cached))
			}

			return cache.failed.contains(key) ? .some(nil) : nil
		}

		if let remembered {
			return remembered?.expression
		}

		let expression: NSRegularExpression
		expressionCache.withLock { $0.compilations[key, default: 0] += 1 }

		do {
			expression = try NSRegularExpression(
				pattern: pattern,
				options: caseless ? .caseInsensitive : []
			)
		} catch {
			let isFirstFailure = expressionCache.withLock { cache in
				if cache.failed.count >= expressionCacheLimit {
					cache.failed.removeAll(keepingCapacity: true)
					cache.compilations.removeAll(keepingCapacity: true)
				}

				return cache.failed.insert(key).inserted
			}

			if isFirstFailure {
				logger.error(
					"Could not compile regular expression: \(error.localizedDescription, privacy: .public)"
				)
			}

			return nil
		}

		expressionCache.withLock { cache in
			if cache.compiled.count >= expressionCacheLimit {
				cache.compiled.removeAll(keepingCapacity: true)
				cache.compilations.removeAll(keepingCapacity: true)
			}

			cache.compiled[key] = CompiledExpression(expression: expression)
		}

		return expression
	}
}

public extension RegularExpression {
	// MARK: - Pattern Safety

	/** Whether `pattern` wraps an unbounded repetition around a body that can
	 already match the same text in more than one way — `(a+)+`, `(\d+)*`,
	 `((x*))+`, `(?:[a-z]+\s?)+`.

	 That is the shape that turns a few dozen characters of input into
	 exponential backtracking, and ICU offers no match budget to stop it: every
	 part of the body is optional or unboundedly repeated, so the engine has an
	 exponential number of ways to divide a subject between the inner repetition
	 and the outer one, and it tries all of them before reporting no match.

	 It is a heuristic, and deliberately a narrow one, because what it reports is
	 shown to a person who is typing a pattern. A repeated group with anything
	 mandatory in its body has one division to try and is left alone — `(#\w+ )+`
	 and `(\w+, )+` are patterns people write — and so is any repetition with a
	 ceiling, `(a{1,2}){1,2}` and `(\d{1,3}\.){1,4}` included, whose cost is
	 bounded by its own limits. The input-length cap is what bounds the rest. */
	static func hasNestedQuantifier(_ pattern: String) -> Bool {
		let characters = Array(pattern)
		/* One scan per open group, the last being the group being read. Index 0
		 stands for the pattern outside every group. */
		var scans = [BranchScan()]
		var index = 0

		while index < characters.count {
			switch characters[index] {
			case "(":
				scans.append(BranchScan())
				index = groupBodyStart(after: index, in: characters)
			case ")":
				var group = scans.count > 1 ? scans.removeLast() : BranchScan()
				group.endBranch()
				let repetition = repetition(at: index + 1, in: characters)

				if repetition.isUnbounded, group.hasAmbiguousBranch {
					return true
				}

				/* The group is one element of whatever encloses it. A group that
				 is ambiguous on its own counts as unbounded there even without a
				 quantifier of its own, which is what `((x*))+` turns on. */
				scans[scans.count - 1].add(
					isUnbounded: repetition.isUnbounded || group.hasAmbiguousBranch,
					isOptional: repetition.isOptional
				)
				index = repetition.end
			case "|":
				scans[scans.count - 1].endBranch()
				index += 1
			default:
				let atomEnd = atomEnd(at: index, in: characters)
				let repetition = repetition(at: atomEnd, in: characters)
				scans[scans.count - 1].add(
					isUnbounded: repetition.isUnbounded,
					isOptional: repetition.isOptional
				)
				index = repetition.end
			}
		}

		return false
	}

	/** One branch of one group, as the scan reads it.

	 A branch is ambiguous when every element in it can vary in length and at
	 least one of them is unbounded: that is when wrapping an unbounded
	 repetition around it has more than one way to divide a subject. */
	private struct BranchScan {
		private var elementCount = 0
		private var variableCount = 0
		private var unboundedCount = 0
		private var sawAmbiguousBranch = false

		/// Whether this branch, or an earlier branch of the same group, is
		/// ambiguous.
		var hasAmbiguousBranch: Bool {
			sawAmbiguousBranch || branchIsAmbiguous
		}

		private var branchIsAmbiguous: Bool {
			elementCount > 0 && variableCount == elementCount && unboundedCount > 0
		}

		mutating func add(isUnbounded: Bool, isOptional: Bool) {
			elementCount += 1

			if isUnbounded {
				unboundedCount += 1
			}

			if isUnbounded || isOptional {
				variableCount += 1
			}
		}

		/// Closes the branch an alternation ends, or the group ends.
		mutating func endBranch() {
			sawAmbiguousBranch = hasAmbiguousBranch
			elementCount = 0
			variableCount = 0
			unboundedCount = 0
		}
	}

	/// Where a group's body starts: past the `(`, and past the `?:`, `?=`, `?!`,
	/// `?<=`, `?<!` or `?<name>` that says what kind of group it is. A lookaround
	/// is read as an ordinary group, which is what it costs to match.
	private static func groupBodyStart(after index: Int, in characters: [Character]) -> Int {
		var start = index + 1
		guard start < characters.count, characters[start] == "?" else { return start }
		start += 1
		guard start < characters.count else { return start }

		switch characters[start] {
		case ":", "=", "!", ">":
			return start + 1
		case "<":
			if start + 1 < characters.count, characters[start + 1] == "=" || characters[start + 1] == "!" {
				return start + 2
			}

			// A named group: `?<name>`, or `?P<name>` with the P already read.
			var end = start + 1
			while end < characters.count, characters[end] != ">" {
				end += 1
			}
			return min(end + 1, characters.count)
		case "P":
			return groupBodyStart(after: start, in: characters)
		default:
			// An inline flag group, `(?i)` or `(?i:…)`: read the flags as flags.
			var end = start
			while end < characters.count, characters[end] != ":", characters[end] != ")" {
				end += 1
			}
			return characters.indices.contains(end) && characters[end] == ":" ? end + 1 : end
		}
	}

	/// Where the atom starting at `index` ends: one character, an escape and what
	/// it escapes, or a whole character class.
	private static func atomEnd(at index: Int, in characters: [Character]) -> Int {
		switch characters[index] {
		case "\\":
			return min(index + 2, characters.count)
		case "[":
			var end = index + 1

			// A `]` as the first member is a literal, and an escape hides one.
			if end < characters.count, characters[end] == "^" {
				end += 1
			}

			if end < characters.count, characters[end] == "]" {
				end += 1
			}

			while end < characters.count, characters[end] != "]" {
				end += characters[end] == "\\" ? 2 : 1
			}

			return min(end + 1, characters.count)
		default:
			return index + 1
		}
	}

	/** The repetition applied to the atom that ends at `index`.

	 `isUnbounded` is what makes a repetition dangerous: `*`, `+` and `{n,}` have
	 no ceiling, while `{2}` and `{1,3}` bound their own cost. `isOptional` says
	 the atom can be skipped, which is what lets a body vary in length without
	 repeating. `end` is where scanning resumes, past a lazy or possessive
	 modifier. */
	private struct Repetition {
		var isUnbounded = false
		var isOptional = false
		var end: Int
	}

	private static func repetition(at index: Int, in characters: [Character]) -> Repetition {
		guard index < characters.count else { return Repetition(end: index) }

		switch characters[index] {
		case "*":
			return Repetition(
				isUnbounded: true,
				isOptional: true,
				end: modifierEnd(after: index + 1, in: characters)
			)
		case "+":
			return Repetition(isUnbounded: true, end: modifierEnd(after: index + 1, in: characters))
		case "?":
			return Repetition(isOptional: true, end: modifierEnd(after: index + 1, in: characters))
		case "{":
			return boundedRepetition(at: index, in: characters)
		default:
			return Repetition(end: index)
		}
	}

	/// `{n}`, `{n,}` or `{n,m}`, or nothing where the brace is a literal one.
	private static func boundedRepetition(at index: Int, in characters: [Character]) -> Repetition {
		guard let close = characters[index...].firstIndex(of: "}") else {
			return Repetition(end: index + 1)
		}

		let body = String(characters[(index + 1) ..< close])
		let bounds = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)

		guard bounds.count <= 2, bounds.allSatisfy({ $0.allSatisfy(\.isNumber) }),
		      bounds.first?.isEmpty == false
		else {
			return Repetition(end: index + 1)
		}

		return Repetition(
			isUnbounded: bounds.count == 2 && bounds[1].isEmpty,
			isOptional: Int(bounds[0]) == 0,
			end: modifierEnd(after: close + 1, in: characters)
		)
	}

	/// Past a `?` or `+` that makes a repetition lazy or possessive. Neither
	/// changes what the repetition can match, and reading one as an atom of its
	/// own would make a body look as though it had something mandatory in it.
	private static func modifierEnd(after index: Int, in characters: [Character]) -> Int {
		guard index < characters.count, characters[index] == "?" || characters[index] == "+" else {
			return index
		}

		return index + 1
	}
}

private extension String {
	var fullRange: NSRange {
		NSRange(startIndex ..< endIndex, in: self)
	}
}
