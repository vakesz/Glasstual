/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import os

private nonisolated let addressBookMatcherLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCAddressBook"
)

/// One element of a compiled hostmask glob.
nonisolated enum IRCHostmaskGlobToken: Equatable {
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
nonisolated enum IRCHostmaskGlob {
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

	/// `tokens` must already be case folded by `compile(_:)` of a lowercased
	/// hostmask; the subject is folded here.
	static func matches(tokens: [IRCHostmaskGlobToken], subject: String) -> Bool {
		let subject = Array(subject.lowercased().unicodeScalars)

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
public final nonisolated class AddressBookEntryMatcher: NSObject {
	@objc public let regularExpressionPattern: String
	@objc public let trackingNickname: String?

	private let globTokens: [IRCHostmaskGlobToken]?
	private let regularExpression: NSRegularExpression?

	@objc(initWithEntryType:hostmask:)
	public init(entryType: IRCAddressBookEntryType, hostmask: String) {
		switch entryType {
		case .ignore:
			regularExpressionPattern = IRCHostmaskGlob.regularExpressionPattern(for: hostmask)
			globTokens = IRCHostmaskGlob.compile(hostmask.lowercased())
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
			return IRCHostmaskGlob.matches(tokens: globTokens, subject: hostmask)
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
