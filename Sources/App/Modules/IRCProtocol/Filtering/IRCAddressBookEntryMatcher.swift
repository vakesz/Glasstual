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

@objc(IRCAddressBookEntryMatcher)
public final class AddressBookEntryMatcher: NSObject {
	@objc public let regularExpressionPattern: String
	@objc public let trackingNickname: String?

	private let regularExpression: NSRegularExpression?

	@objc(initWithEntryType:hostmask:)
	public init(entryType: IRCAddressBookEntryType, hostmask: String) {
		switch entryType {
		case .ignore:
			let escapedHostmask = NSRegularExpression.escapedPattern(for: hostmask)
				.replacingOccurrences(of: #"\*"#, with: ".*?")
				.replacingOccurrences(of: #"\?"#, with: ".")

			regularExpressionPattern = "^\(escapedHostmask)$"
			trackingNickname = nil
		case .userTracking:
			let escapedHostmask = NSRegularExpression.escapedPattern(for: hostmask)

			regularExpressionPattern = "^\(escapedHostmask)!(.*?)@(.*?)$"
			trackingNickname = Self.nickname(from: hostmask)
		case .mixed:
			regularExpressionPattern = ""
			trackingNickname = nil
		@unknown default:
			regularExpressionPattern = ""
			trackingNickname = nil
		}

		regularExpression =
			regularExpressionPattern.isEmpty
				? nil
				: try? NSRegularExpression(pattern: regularExpressionPattern, options: [.caseInsensitive])

		super.init()
	}

	@objc(matchesHostmask:)
	public func matches(hostmask: String) -> Bool {
		guard let regularExpression else {
			return false
		}

		let range = NSRange(hostmask.startIndex ..< hostmask.endIndex, in: hostmask)

		return regularExpression.firstMatch(in: hostmask, range: range) != nil
	}

	private static func nickname(from hostmask: String) -> String {
		guard let separator = hostmask.firstIndex(of: "!") else {
			return hostmask
		}

		return String(hostmask[..<separator])
	}
}
