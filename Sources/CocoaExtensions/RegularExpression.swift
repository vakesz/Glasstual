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

	/** Everything the cache remembers about a pattern.

	 `NSRegularExpression` is declared `NS_SWIFT_SENDABLE` by Foundation and is
	 immutable once built, so this is a value whose every member is `Sendable` —
	 which is what the `Mutex` guarding it asks for.

	 A pattern that fails to compile is remembered too. Patterns come from the
	 user's message rules and highlight words, and are tried once per incoming
	 message, so a broken one used to be recompiled — and re-logged —
	 for every line that arrived. Recording the failure makes the second attempt
	 as cheap as a hit and keeps the log to one line per distinct pattern. */
	private struct ExpressionCache {
		var compiled: [CacheKey: NSRegularExpression] = [:]
		var failed: Set<CacheKey> = []
	}

	/// What the cache knows about one pattern, which is not the same question as
	/// whether it compiles: a pattern nothing has tried yet has to be tried.
	private enum CacheLookup {
		case compiled(NSRegularExpression)
		case failed
		case unknown
	}

	private static let logger = Logger(
		subsystem: Logging.frameworkSubsystem,
		category: "RegularExpression"
	)

	/** Patterns here come from the user's message rules and highlight words, and
	 are evaluated once per incoming message. Compiling is the
	 expensive part, so hold on to the result; `NSRegularExpression` is
	 immutable and safe to match on from several threads. */
	private static let expressionCache = Mutex(ExpressionCache())

	/// Beyond this the cache is emptied rather than grown. Real use has a few
	/// dozen distinct patterns; a much larger number means something is
	/// generating them, not reusing them.
	private static let expressionCacheLimit = 512

	/** The longest input the entry points hand to ICU.

	 ICU matches by backtracking, so the cost of a badly shaped pattern grows
	 with the subject as well as with the pattern. The subjects here are remote:
	 a chat filter is matched against whatever a peer sends. An IRC line is 512
	 bytes, and even a tagged or multiline one stays far below this, so the cap
	 only ever bites on something that is not a chat message. */
	public static let inputLengthLimit = 4096

	/** How long one evaluation may run before it is abandoned.

	 The input cap bounds the subject, but not what a pattern does with it:
	 `(.|\s)*x` takes seconds over two dozen spaces. The budget is what bounds
	 that, on whatever actor the caller matches on. */
	public static let matchBudget = Duration.milliseconds(50)

	/// How one budgeted evaluation ended.
	public enum MatchOutcome: Sendable {
		case matched
		case unmatched
		/// ICU was stopped when the budget ran out, so the pattern neither matched
		/// nor failed to; callers treat it as no match.
		case exceededBudget
		/// The pattern does not compile.
		case invalidPattern
	}

	/** How matching `needle` against `haystack` ends, within `budget`.

	 ICU reports progress to the block periodically while a single match
	 attempt backtracks, which is the only point at which a runaway evaluation
	 can be stopped from outside. */
	public static func firstMatch(
		of needle: String,
		in haystack: String,
		withoutCase caseless: Bool = false,
		inputLimit: Int = inputLengthLimit,
		budget: Duration = matchBudget
	) -> MatchOutcome {
		guard let expression = Self.expression(for: needle, caseless: caseless) else { return .invalidPattern }
		let subject = boundedInput(haystack, limit: inputLimit)
		var outcome = MatchOutcome.unmatched
		let deadline = ContinuousClock.now.advanced(by: budget)

		expression.enumerateMatches(in: subject, options: .reportProgress, range: subject.fullRange) { result, _, stop in
			if result != nil {
				outcome = .matched
				stop.pointee = true
			} else if ContinuousClock.now >= deadline {
				outcome = .exceededBudget
				stop.pointee = true
			}
		}

		return outcome
	}

	/// Every match of `needle` in `haystack`, or every capture group of every
	/// match when `substringGroups` is set, with the same bound on the subject as
	/// ``firstMatch(of:in:withoutCase:inputLimit:budget:)``.
	public static func matches(
		in haystack: String,
		withRegex needle: String,
		withoutCase caseless: Bool,
		substringGroups: Bool,
		inputLimit: Int = inputLengthLimit
	) -> [String] {
		let subject = boundedInput(haystack, limit: inputLimit)
		guard let expression = Self.expression(for: needle, caseless: caseless) else { return [] }

		return expression.matches(in: subject, range: subject.fullRange).flatMap { result in
			let ranges = substringGroups ? (0 ..< result.numberOfRanges) : (0 ..< 1)
			return ranges.compactMap { index -> String? in
				let range = result.range(at: index)
				guard range.location != NSNotFound, let swiftRange = Range(range, in: subject) else { return nil }
				return String(subject[swiftRange])
			}
		}
	}

	/// `haystack` cut to at most `limit` characters, so a user-authored pattern
	/// is bounded in what it is allowed to do on remote input. Cutting by
	/// characters rather than by code units keeps a subject from ending in half
	/// of a grapheme.
	private static func boundedInput(_ haystack: String, limit: Int) -> String {
		guard limit > 0 else { return "" }
		guard haystack.count > limit else { return haystack }

		return String(haystack.prefix(limit))
	}

	/// `pattern` compiled, from the cache when it has been compiled before.
	///
	/// Compiling is the expensive part and the result is immutable, so a caller
	/// that matches the same pattern against many subjects asks once and holds
	/// nothing itself. A pattern that does not compile is remembered as such and
	/// answers `nil` without being tried again.
	public static func expression(for pattern: String, caseless: Bool = false) -> NSRegularExpression? {
		let key = CacheKey(pattern: pattern, caseless: caseless)

		let remembered = expressionCache.withLock { cache -> CacheLookup in
			if let cached = cache.compiled[key] {
				return .compiled(cached)
			}

			return cache.failed.contains(key) ? .failed : .unknown
		}

		switch remembered {
		case let .compiled(expression): return expression
		case .failed: return nil
		case .unknown: break
		}

		let expression: NSRegularExpression

		do {
			expression = try NSRegularExpression(
				pattern: pattern,
				options: caseless ? .caseInsensitive : []
			)
		} catch {
			let isFirstFailure = expressionCache.withLock { cache in
				if cache.failed.count >= expressionCacheLimit {
					cache.failed.removeAll(keepingCapacity: true)
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
			}

			cache.compiled[key] = expression
		}

		return expression
	}
}

private extension String {
	var fullRange: NSRange {
		NSRange(startIndex ..< endIndex, in: self)
	}
}
