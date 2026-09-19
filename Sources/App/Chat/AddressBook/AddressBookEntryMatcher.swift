// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One element of a compiled hostmask glob.
nonisolated enum HostmaskGlobToken: Equatable, Sendable {
	case literal(Unicode.Scalar)
	/// `?`
	case anyCharacter
	/// `*`
	case anySequence
}

/// Compiles and runs hostmask globs.
///
/// Translating a glob into a regular expression (`*` becomes `.*?`) is
/// exponentially backtrackable: six wildcards against a 70 character
/// hostmask took seconds, nine took minutes, on the main thread, against a
/// server-controlled subject. This matcher is linear in the worst case.
nonisolated enum HostmaskGlob {
	/// `\` escapes the character that follows it, so a mask can contain a
	/// literal `*` or `?`; anywhere else it is an ordinary character.
	static func compile(_ hostmask: String) -> [HostmaskGlobToken] {
		var tokens: [HostmaskGlobToken] = []
		var scalars = Substring(hostmask).unicodeScalars[...]

		while let scalar = scalars.first {
			scalars = scalars.dropFirst()

			switch scalar {
			case "*":
				// Adjacent wildcards add nothing but backtracking.
				if tokens.last != .anySequence {
					tokens.append(.anySequence)
				}
			case "?":
				tokens.append(.anyCharacter)
			case "\\":
				guard let escaped = scalars.first else {
					tokens.append(.literal(scalar))
					continue
				}

				scalars = scalars.dropFirst()
				tokens.append(.literal(escaped))
			default:
				tokens.append(.literal(scalar))
			}
		}

		return tokens
	}

	/// Folds a hostmask for matching.
	///
	/// A nickname is a byte string with its own case rules: RFC 1459 §2.2
	/// makes `[`, `]`, `\` and `~` the upper-case forms of `{`, `}`, `|` and
	/// `^`, so an ignore on `nick[home]` has to match `nick{home}`. Swift's
	/// `lowercased()` knows neither that nor where to stop — it folds
	/// non-ASCII letters too, which no server does.
	static func casefold(_ value: String, caseMapping: ISupportCaseMapping) -> String {
		IRCCaseFolding.fold(value, using: caseMapping)
	}

	/// The compiled mask with every literal folded.
	///
	/// Folding the mask *before* compiling would eat its syntax: `\` is both
	/// the escape character and the upper-case form of `|`, so `a\*b` would
	/// fold to `a|*b` and stop meaning "a literal asterisk".
	static func compile(_ hostmask: String, caseMapping: ISupportCaseMapping) -> [HostmaskGlobToken] {
		compile(hostmask).map { token in
			guard case let .literal(scalar) = token else {
				return token
			}

			let folded = casefold(String(scalar), caseMapping: caseMapping)

			return .literal(folded.unicodeScalars.first ?? scalar)
		}
	}

	/// `tokens` must already be folded by `casefold(_:caseMapping:)` under the
	/// same mapping; the subject is folded here.
	static func matches(
		tokens: [HostmaskGlobToken],
		subject: String,
		caseMapping: ISupportCaseMapping
	) -> Bool {
		let subject = Array(casefold(subject, caseMapping: caseMapping).unicodeScalars)

		var tokenIndex = 0
		var subjectIndex = 0
		var wildcardTokenIndex: Int?
		var wildcardSubjectIndex = 0

		while subjectIndex < subject.count {
			if tokenIndex < tokens.count {
				switch tokens[tokenIndex] {
				case .anySequence:
					wildcardTokenIndex = tokenIndex
					wildcardSubjectIndex = subjectIndex
					tokenIndex += 1
					continue
				case .anyCharacter:
					tokenIndex += 1
					subjectIndex += 1
					continue
				case let .literal(scalar) where scalar == subject[subjectIndex]:
					tokenIndex += 1
					subjectIndex += 1
					continue
				case .literal:
					break
				}
			}

			// Give the most recent `*` one more character and try again.
			guard let wildcardTokenIndex else {
				return false
			}

			tokenIndex = wildcardTokenIndex + 1
			wildcardSubjectIndex += 1
			subjectIndex = wildcardSubjectIndex
		}

		while tokenIndex < tokens.count, tokens[tokenIndex] == .anySequence {
			tokenIndex += 1
		}

		return tokenIndex == tokens.count
	}

	/// The equivalent regular expression, kept for display only.
	static func regularExpressionPattern(for hostmask: String) -> String {
		var pattern = "^"

		for token in compile(hostmask) {
			switch token {
			case .anySequence:
				pattern += ".*?"
			case .anyCharacter:
				pattern += "."
			case let .literal(scalar):
				pattern += NSRegularExpression.escapedPattern(for: String(scalar))
			}
		}

		return pattern + "$"
	}
}

/** The compiled form of one address-book hostmask.

 A value rather than a class: everything it holds is one, and an
 `AddressBookEntry` stores it, so a reference here made a struct that claims to
 be a value type hold a reference after all. */
nonisolated struct AddressBookEntryMatcher: Sendable {
	let regularExpressionPattern: String
	let trackingNickname: String?

	private let globTokens: [HostmaskGlobToken]?
	private let caseMapping: ISupportCaseMapping

	/// An address book entry belongs to no one connection — the same ignore
	/// applies on every network — so it folds under `rfc1459`, the mapping a
	/// server that advertises none is assumed to use.
	init(
		entryType: AddressBookEntryKind,
		hostmask: String,
		caseMapping: ISupportCaseMapping = .rfc1459
	) {
		self.caseMapping = caseMapping

		switch entryType {
		case .ignore:
			regularExpressionPattern = HostmaskGlob.regularExpressionPattern(for: hostmask)
			globTokens = HostmaskGlob.compile(hostmask, caseMapping: caseMapping)
			trackingNickname = nil
		case .userTracking:
			/* A tracking entry names a person, so it matches that nickname at
			 whatever user@host they connect from. Compiled through the same glob
			 matcher as an ignore because one casemapping has to govern the whole
			 address book: `NSRegularExpression`'s `.caseInsensitive` is Unicode
			 folding, under which a tracking entry for `nick[home]` missed
			 `nick{home}` while an ignore for the same mask matched it. */
			let mask = Self.escapedGlobLiteral(Self.nickname(from: hostmask)) + "!*@*"

			regularExpressionPattern = HostmaskGlob.regularExpressionPattern(for: mask)
			globTokens = HostmaskGlob.compile(mask, caseMapping: caseMapping)
			trackingNickname = Self.nickname(from: hostmask)
		case .mixed:
			regularExpressionPattern = ""
			globTokens = nil
			trackingNickname = nil
		@unknown default:
			regularExpressionPattern = ""
			globTokens = nil
			trackingNickname = nil
		}
	}

	func matches(hostmask: String) -> Bool {
		guard let globTokens else {
			return false
		}

		return HostmaskGlob.matches(
			tokens: globTokens,
			subject: hostmask,
			caseMapping: caseMapping
		)
	}

	/// `value` as a mask that matches itself: a nickname the user typed is a
	/// literal, so a glob metacharacter in it must not become a wildcard.
	private static func escapedGlobLiteral(_ value: String) -> String {
		var escaped = ""

		for character in value {
			if character == "*" || character == "?" || character == "\\" {
				escaped.append("\\")
			}

			escaped.append(character)
		}

		return escaped
	}

	private static func nickname(from hostmask: String) -> String {
		guard let separator = hostmask.firstIndex(of: "!") else {
			return hostmask
		}

		return String(hostmask[..<separator])
	}
}
