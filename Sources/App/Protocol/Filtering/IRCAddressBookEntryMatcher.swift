/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import os

private nonisolated let addressBookMatcherLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCAddressBook"
)

/// One element of a compiled hostmask glob.
nonisolated enum IRCHostmaskGlobToken: Equatable, Sendable { // nonisolated: value
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
nonisolated enum IRCHostmaskGlob { // nonisolated: value
	/// `\` escapes the character that follows it, so a mask can contain a
	/// literal `*` or `?`; anywhere else it is an ordinary character.
	static func compile(_ hostmask: String) -> [IRCHostmaskGlobToken] {
		var tokens: [IRCHostmaskGlobToken] = []
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
	static func casefold(_ value: String, caseMapping: IRCISupportInfoCaseMapping) -> String {
		ISupportTokenParser.casefold(value, caseMapping: caseMapping)
	}

	/// The compiled mask with every literal folded.
	///
	/// Folding the mask *before* compiling would eat its syntax: `\` is both
	/// the escape character and the upper-case form of `|`, so `a\*b` would
	/// fold to `a|*b` and stop meaning "a literal asterisk".
	static func compile(_ hostmask: String, caseMapping: IRCISupportInfoCaseMapping) -> [IRCHostmaskGlobToken] {
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
		tokens: [IRCHostmaskGlobToken],
		subject: String,
		caseMapping: IRCISupportInfoCaseMapping
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

@objc(IRCAddressBookEntryMatcher)
public final nonisolated class AddressBookEntryMatcher: NSObject, Sendable { // nonisolated: value
	@objc public let regularExpressionPattern: String
	@objc public let trackingNickname: String?

	private let globTokens: [IRCHostmaskGlobToken]?
	private let regularExpression: NSRegularExpression?
	private let caseMapping: IRCISupportInfoCaseMapping

	/// An address book entry belongs to no one connection — the same ignore
	/// applies on every network — so it folds under `rfc1459`, the mapping a
	/// server that advertises none is assumed to use.
	@objc(initWithEntryType:hostmask:)
	public convenience init(entryType: IRCAddressBookEntryType, hostmask: String) {
		self.init(entryType: entryType, hostmask: hostmask, caseMapping: .rfc1459)
	}

	public init(
		entryType: IRCAddressBookEntryType,
		hostmask: String,
		caseMapping: IRCISupportInfoCaseMapping
	) {
		self.caseMapping = caseMapping

		switch entryType {
		case .ignore:
			regularExpressionPattern = IRCHostmaskGlob.regularExpressionPattern(for: hostmask)
			globTokens = IRCHostmaskGlob.compile(hostmask, caseMapping: caseMapping)
			trackingNickname = nil
			regularExpression = nil
		case .userTracking:
			let escapedHostmask = NSRegularExpression.escapedPattern(for: hostmask)

			regularExpressionPattern = "^\(escapedHostmask)!(.*?)@(.*?)$"
			globTokens = nil
			trackingNickname = Self.nickname(from: hostmask)
			regularExpression = Self.compiledExpression(regularExpressionPattern)
		case .mixed:
			regularExpressionPattern = ""
			globTokens = nil
			trackingNickname = nil
			regularExpression = nil
		@unknown default:
			regularExpressionPattern = ""
			globTokens = nil
			trackingNickname = nil
			regularExpression = nil
		}

		super.init()
	}

	@objc(matchesHostmask:)
	public func matches(hostmask: String) -> Bool {
		if let globTokens {
			return IRCHostmaskGlob.matches(
				tokens: globTokens,
				subject: hostmask,
				caseMapping: caseMapping
			)
		}

		guard let regularExpression else {
			return false
		}

		let range = NSRange(hostmask.startIndex ..< hostmask.endIndex, in: hostmask)

		return regularExpression.firstMatch(in: hostmask, range: range) != nil
	}

	private static func compiledExpression(_ pattern: String) -> NSRegularExpression? {
		do {
			return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
		} catch {
			addressBookMatcherLogger.error(
				"Failed to compile hostmask regular expression: \(error.localizedDescription, privacy: .public)"
			)

			return nil
		}
	}

	private static func nickname(from hostmask: String) -> String {
		guard let separator = hostmask.firstIndex(of: "!") else {
			return hostmask
		}

		return String(hostmask[..<separator])
	}
}
