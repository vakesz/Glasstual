/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import OSLog
import Synchronization

private nonisolated let highlightExpressionLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogRenderer"
)

/** The compiled form of the highlight keywords, kept between rendered lines.

 In Regular Expression mode every keyword was compiled once per keyword per
 line: a dozen patterns cost a dozen compilations for every message a busy
 channel prints, and a pattern that cannot compile paid for its own failure
 just as often. Compiling once and keeping a bounded number of the results
 turns that into a dictionary lookup.

 Rendering runs off the main actor on several lines at a time, so the store is
 a `Mutex` around a value this type never lets out. What it holds are
 `NSRegularExpression`s, which Foundation documents as immutable and safe to
 match from several threads; nothing here mutates one. */
final nonisolated class TranscriptHighlightExpressions: Sendable { // nonisolated: immutable
	/// Enough for the keyword lists people actually keep, and small enough that
	/// a channel-specific list cannot grow the store without bound.
	private static let capacity = 64

	/** How much of a line one of the reader's own patterns is matched against.

	 A pathological pattern costs time in proportion to the input, and IRC
	 lines arrive from strangers. Four kilobytes is far past any real message
	 and far short of anything that could stall a render. It bounds the patterns
	 that come through this store and nothing else: the renderer's own fixed
	 patterns cannot backtrack, and capping them only stopped a channel name
	 late in a long line from being a link. */
	static let maximumMatchedLength = 4096

	private struct Store {
		/// Patterns that compiled, least recently used first.
		var order: [String] = []
		var expressions: [String: NSRegularExpression] = [:]
		/// Patterns that did not compile, so the attempt and its log line are
		/// paid once rather than once a line.
		var failures: Set<String> = []
	}

	private let store = Mutex(Store())

	/// The one cache the renderer uses. Patterns come from the reader's own
	/// preferences, so there is nothing per view to keep apart.
	static let shared = TranscriptHighlightExpressions()

	/// The compiled form of `pattern`, or `nil` when it does not compile.
	func expression(for pattern: String) -> NSRegularExpression? {
		enum Lookup {
			case hit(NSRegularExpression)
			case knownFailure
			case unknown
		}

		let lookup = store.withLock { store -> Lookup in
			if let expression = store.expressions[pattern] {
				store.order.removeAll { $0 == pattern }
				store.order.append(pattern)
				return .hit(expression)
			}
			return store.failures.contains(pattern) ? .knownFailure : .unknown
		}
		switch lookup {
		case let .hit(expression): return expression
		case .knownFailure: return nil
		case .unknown: break
		}

		let compiled = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
		if compiled == nil {
			highlightExpressionLogger.error("Highlight pattern did not compile; it will be ignored")
		}
		return store.withLock { store -> NSRegularExpression? in
			guard let compiled else {
				if store.failures.count >= Self.capacity {
					store.failures.removeFirst()
				}
				store.failures.insert(pattern)
				return nil
			}
			store.expressions[pattern] = compiled
			store.order.removeAll { $0 == pattern }
			store.order.append(pattern)
			while store.order.count > Self.capacity {
				store.expressions.removeValue(forKey: store.order.removeFirst())
			}
			return compiled
		}
	}
}
