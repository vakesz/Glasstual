// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One thing an ISUPPORT token says, as a value.

 ``reading(_:value:)`` turns a token into the changes it asks for and touches
 nothing; ``ISupport`` applies them in order to its table. Keeping the reading
 apart from the table is what lets it be checked token by token without a
 table to inspect. */
nonisolated enum ISupportChange: Sendable, Equatable {
	/// A length or a count a token's value sets.
	nonisolated enum Count: Sendable, Equatable {
		case awayLength, channelNameLength, chatHistoryLines, keyLength, kickLength, lineLength
		case targets, modes, monitorEntries, watchEntries, nicknameLength, topicLength
	}

	/// A mode letter a token names, or leaves at the usual one.
	nonisolated enum ModeLetter: Sendable, Equatable {
		case bot, callerID, deaf, banException, inviteException
	}

	/// What a token announces by being present at all.
	nonisolated enum Feature: Sendable, Equatable {
		case safeList, utf8Only, whox
	}

	case count(Count, UInt)
	case modeSymbol(ModeLetter, String)
	case feature(Feature)

	case caseMapping(ISupportCaseMapping)
	/// `CHANMODES`, which replaces the advertised table rather than adding to it.
	case channelModeKinds([Character: ChannelModeKind])
	case channelNamePrefixes([String])
	case networkName(String)
	/// `PREFIX`, as two lists of equal length. Both are empty when the server
	/// has no membership prefixes at all.
	case userModePrefixes(modeSymbols: [String], characters: [String])
	case statusMessagePrefixCharacters([String])
	case channelLimits([Character: UInt])
	case clientTagDenyList([String])
	case chatHistoryReferences(timestamps: Bool, messageIdentifiers: Bool)
	case extendedListTokens([String])
	case extendedBan(prefix: String?, types: [String])
	case maximumListEntries([Character: UInt])
	case maximumTargetsByCommand([String: UInt])
	/// `SILENCE`, with the list's size when the server gave one.
	case silenceSupported(maximumEntries: UInt?)

	/// A capability the token is the only evidence for.
	case enablesCapability(CapabilitySet)
	/// A capability the server turns on with a pre-CAP line.
	case legacyCapability(ISupportEffects.LegacyCapability)

	/** What `token` asks for, in the order it is to be applied: its value first,
	 then what it says by being present at all.

	 `value` is the unescaped value, or `nil` for a token sent without one. */
	static func reading(_ token: ISupportToken, value: String?) -> [ISupportChange] {
		var changes: [ISupportChange] = []
		if let value, let change = valueChange(token, value: value) {
			changes.append(change)
		}
		changes += announcementChanges(token, value: value)
		return changes
	}
}

// MARK: - Reading a token's value

private nonisolated extension ISupportChange {
	/** Reads the value half of a token.

	 A token whose value is a count is read as one first, so that a count the
	 token does not take (`NETWORK=42`) still falls through to the text reading
	 that does. */
	static func valueChange(_ token: ISupportToken, value: String) -> ISupportChange? {
		if let count = positiveInteger(from: value), let change = countChange(token, count: count) {
			return change
		}

		switch token {
		case .casemapping:
			return .caseMapping(caseMapping(named: value))
		case .chanmodes:
			/* A re-sent CHANMODES replaces the table rather than adding to it,
			 so a shorter one does not leave the modes it dropped behind. */
			return .channelModeKinds(ISupportTokenParser.channelModeKinds(from: value, merging: [:]))
		case .chantypes:
			/* An empty CHANTYPES is the server saying it supports no channel
			 types at all, which is not the same as it saying nothing. */
			return .channelNamePrefixes(value.map(String.init))
		case .network:
			return .networkName(value)
		case .prefix:
			return userModePrefixes(value)
		case .statusmsg:
			return .statusMessagePrefixCharacters(value.map(String.init))
		case .chanlimit:
			return .channelLimits(ISupportTokenParser.channelLimits(from: value))
		case .clienttagdeny:
			return .clientTagDenyList(value.components(separatedBy: ","))
		case .msgreftypes:
			let references = value.split(separator: ",")
			return .chatHistoryReferences(
				timestamps: references.contains("timestamp"),
				messageIdentifiers: references.contains("msgid")
			)
		case .elist:
			return .extendedListTokens(value.uppercased().map(String.init))
		case .extban:
			let configuration = ISupportTokenParser.extendedBanConfiguration(from: value)
			return .extendedBan(prefix: configuration.prefix, types: configuration.types)
		case .maxlist:
			return .maximumListEntries(ISupportTokenParser.maximumListEntries(from: value))
		case .targmax:
			return .maximumTargetsByCommand(ISupportTokenParser.maximumTargets(from: value))
		default:
			return nil
		}
	}

	/// The change `count` makes when `token`'s value is a count, or `nil` when
	/// it is not.
	static func countChange(_ token: ISupportToken, count: UInt) -> ISupportChange? {
		switch token {
		case .awaylen:
			.count(.awayLength, count)
		case .channellen:
			.count(.channelNameLength, count)
		case .chathistory:
			.count(.chatHistoryLines, count)
		case .keylen:
			.count(.keyLength, count)
		case .kicklen:
			.count(.kickLength, count)
		case .linelen:
			.count(.lineLength, min(count, UInt(ProtocolLimits.maximumServerLineLength)))
		case .maxtargets:
			.count(.targets, count)
		case .modes:
			.count(.modes, count)
		/* The count is the whole point of these two: past it the server answers
		 ERR_MONLISTFULL or ERR_TOOMANYWATCH and the tail of the list is simply
		 not tracked. The flag half of the token still enables the capability. */
		case .monitor:
			.count(.monitorEntries, count)
		case .watch:
			.count(.watchEntries, count)
		case .nicklen:
			.count(.nicknameLength, count)
		case .topiclen:
			.count(.topicLength, count)
		default:
			nil
		}
	}

	/** A token's value as a count.

	 `NSString.integerValue` used to do this, which accepts trailing junk
	 (`NICKLEN=50abc` read as 50) and saturates at `Int.max` on overflow instead
	 of rejecting, which is how `LINELEN=99999999999999999999` turned into a
	 line budget that never split anything. */
	static func positiveInteger(from value: String) -> UInt? {
		guard let parsedValue = UInt(value), parsedValue > 0 else {
			return nil
		}

		return parsedValue
	}

	static func caseMapping(named name: String) -> ISupportCaseMapping {
		if name.caseInsensitiveCompare("ascii") == .orderedSame {
			.ascii
		} else if name.caseInsensitiveCompare("strict-rfc1459") == .orderedSame {
			.strictRFC1459
		} else if name.caseInsensitiveCompare("rfc8265") == .orderedSame
			|| name.caseInsensitiveCompare("rfc7613") == .orderedSame
		{
			/* RFC 8265 obsoletes RFC 7613 and keeps its casefold; servers
			 advertise either name for the same mapping. */
			.rfc7613
		} else {
			.rfc1459
		}
	}

	static func userModePrefixes(_ modeString: String) -> ISupportChange? {
		/* An empty PREFIX is the server saying it has no membership prefixes,
		 which has to clear the assumed op/voice pair rather than leave it. */
		guard modeString.isEmpty == false else {
			return .userModePrefixes(modeSymbols: [], characters: [])
		}

		guard let configuration = ISupportTokenParser.userPrefixConfiguration(from: modeString) else {
			return nil
		}

		return .userModePrefixes(modeSymbols: configuration.modeSymbols, characters: configuration.characters)
	}
}

// MARK: - Reading a token as an announcement

private nonisolated extension ISupportChange {
	/// Reads what a token says by being present at all, whatever value it
	/// carried.
	static func announcementChanges(_ token: ISupportToken, value: String?) -> [ISupportChange] {
		switch token {
		// Mode letters, which a server may name or leave at the usual one.
		case .bot:
			if let value, value.isModeSymbol {
				return [.modeSymbol(.bot, value)]
			}
			return []
		case .callerid:
			return [.modeSymbol(.callerID, validatedModeSymbol(value, fallback: "g"))]
		case .deaf:
			return [.modeSymbol(.deaf, validatedModeSymbol(value, fallback: "D"))]
		case .excepts:
			return [.modeSymbol(.banException, validatedModeSymbol(value, fallback: "e"))]
		case .invex:
			return [.modeSymbol(.inviteException, validatedModeSymbol(value, fallback: "I"))]
		// Capabilities the token is the only evidence for.
		case .monitor:
			return [.enablesCapability(.monitorCommand)]
		case .watch:
			return [.enablesCapability(.watchCommand)]
		case .namesx:
			return [.legacyCapability(
				ISupportEffects.LegacyCapability(capability: .multiPrefix, command: "PROTOCTL NAMESX")
			)]
		case .uhnames:
			return [.legacyCapability(
				ISupportEffects.LegacyCapability(capability: .userhostInNames, command: "PROTOCTL UHNAMES")
			)]
		// Plain announcements.
		case .safelist:
			return [.feature(.safeList)]
		case .silence:
			return [.silenceSupported(maximumEntries: value.flatMap(positiveInteger(from:)))]
		case .utf8only:
			return [.feature(.utf8Only)]
		case .whox:
			return [.feature(.whox)]
		default:
			return []
		}
	}

	static func validatedModeSymbol(_ value: String?, fallback: String) -> String {
		guard let value, value.isModeSymbol else {
			return fallback
		}

		return value
	}
}
