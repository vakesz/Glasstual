// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// The two prefix modes every server is assumed to have until it says
/// otherwise.
private nonisolated let defaultUserModePrefixPairs: [(modeSymbol: String, character: String)] = [
	(modeSymbol: "o", character: "@"), (modeSymbol: "v", character: "+"),
]

private nonisolated let defaultChannelModeKinds: [Character: ChannelModeKind] = [
	"o": .userPrefix, "v": .userPrefix,
]

final class ISupport {
	var serverAddress: String?
	private(set) var maximumAwayLength: UInt = 0
	private(set) var maximumChannelNameLength: UInt = 0
	private(set) var maximumKeyLength: UInt = 0
	private(set) var maximumKickLength: UInt = 0
	private(set) var maximumNicknameLength: UInt = 0
	private(set) var maximumTopicLength: UInt = 0
	private(set) var maximumModeCount: UInt = 0
	private(set) var maximumLineLength: UInt = 0
	/// `MAXTARGETS`: how many targets any command not named by `TARGMAX` takes,
	/// or zero when the server never sent one.
	private(set) var maximumTargets: UInt = 0
	private(set) var maximumSilenceEntries: UInt = 0
	/// `MONITOR=`: how many entries the server's monitor list holds, or zero
	/// when it advertised the token without a count.
	private(set) var maximumMonitorEntries: UInt = 0
	/// `WATCH=`: the same ceiling for the older watch list.
	private(set) var maximumWatchEntries: UInt = 0
	private(set) var chatHistoryMaximumLines: UInt = 0
	private(set) var silenceSupported = false
	private(set) var safeListSupported = false
	private(set) var whoxSupported = false
	private(set) var utf8Only = false
	private(set) var channelNamePrefixes: [String] = ["#"]
	private(set) var statusMessagePrefixCharacters: [String] = []
	private(set) var extendedBanTypes: [String] = []
	private(set) var extendedListTokens: [String] = []
	private(set) var clientTagDenyList: [String] = []
	/// What class the server put each channel mode in, and therefore whether
	/// the mode carries a parameter.
	private(set) var channelModeKinds: [Character: ChannelModeKind] = defaultChannelModeKinds
	private var advertisedChannelModeKinds: [Character: ChannelModeKind] = [:] {
		didSet { updateChannelModeKinds() }
	}

	/// Missing MSGREFTYPES means both standard reference types are available.
	private(set) var chatHistorySupportsTimestamps = true
	private(set) var chatHistorySupportsMessageIdentifiers = true

	/// `CHANLIMIT`, keyed by channel prefix.
	private(set) var channelLimits: [Character: UInt] = [:]
	/// `MAXLIST`, keyed by list mode.
	private(set) var maximumListEntries: [Character: UInt] = [:]
	/// `TARGMAX`, keyed by uppercased command name. An entry with an empty
	/// limit is stored as zero; ``maximumTargets(forCommand:)`` says what that
	/// is worth.
	private(set) var maximumTargetsByCommand: [String: UInt] = [:]
	/// Mode symbol / prefix character pairs from ISUPPORT `PREFIX=`, stored as
	/// pairs so the two halves can never disagree in length.
	private(set) var userModePrefixPairs = defaultUserModePrefixPairs {
		didSet {
			updateChannelModeKinds()
			rebuildUserPrefixTable()
		}
	}

	/** The same prefixes as a value, and the one copy every prefix question is
	 answered from.

	 Rebuilt when `PREFIX=` or `CASEMAPPING=` changes rather than per question:
	 ranking a member list asks for a rank per member per mode, and the members
	 are ranked off the main actor from this very value. */
	private(set) var userPrefixes = UserPrefixTable()

	private(set) var banExceptionModeSymbol: String?
	private(set) var inviteExceptionModeSymbol: String?
	private(set) var botModeSymbol: String?
	private(set) var callerIDModeSymbol: String?
	private(set) var deafModeSymbol: String?
	private(set) var extendedBanPrefix: String?
	private(set) var networkName: String?
	private(set) var networkNameFormatted: String?
	private(set) var caseMapping: ISupportCaseMapping = .rfc1459 {
		didSet { rebuildUserPrefixTable() }
	}

	/** The `PREFIX` modes as channel-mode kinds.

	 `CHANMODES` never lists them, so they are folded back in every time the
	 channel-mode table is replaced. */
	private var userPrefixModeKinds: [Character: ChannelModeKind] {
		Dictionary(
			userModePrefixPairs.compactMap { pair in
				pair.modeSymbol.first.map { ($0, ChannelModeKind.userPrefix) }
			},
			uniquingKeysWith: { first, _ in first }
		)
	}

	private func updateChannelModeKinds() {
		// PREFIX overrides CHANMODES, but withdrawing a prefix must reveal the
		// original CHANMODES kind rather than erase it.
		channelModeKinds = advertisedChannelModeKinds.merging(userPrefixModeKinds) { _, prefix in prefix }
	}

	/// Rebuilds the table the prefix questions are answered from.
	private func rebuildUserPrefixTable() {
		userPrefixes = UserPrefixTable(
			modeSymbols: userModePrefixPairs.map(\.modeSymbol),
			prefixCharacters: userModePrefixPairs.map(\.character),
			caseMapping: caseMapping
		)
	}

	/** The most recent 005 line, its values unescaped, kept so the numeric
	 handler can spell back out what the server just said.

	 Only the newest line is ever read, and a server may send 005 for as long as
	 it stays connected, so the earlier ones are not kept. */
	private var lastConfiguration: [String: ISupportValue] = [:]
	private var hasReceivedConfiguration = false

	init() {
		/* Two settings do not start out cleared: the mode count and the nickname
		 length begin at the figures the protocol assumes until a server says
		 otherwise, which is what a reset puts back. */
		reset()
	}

	var configurationReceived: Bool {
		hasReceivedConfiguration
	}

	var stringValueForLastUpdate: String? {
		guard lastConfiguration.isEmpty == false else {
			return nil
		}

		return stringValue(forConfiguration: lastConfiguration)
	}

	/** Clears every advertised value, and reports the capability facts the
	 tokens that are going away stood in for. */
	@discardableResult
	func reset() -> ISupportEffects {
		var effects = ISupportEffects()

		lastConfiguration = [:]
		hasReceivedConfiguration = false
		serverAddress = nil
		userModePrefixPairs = defaultUserModePrefixPairs

		for token in ISupportToken.allCases {
			resetSetting(token, into: &effects)
		}

		return effects
	}

	@discardableResult
	func resetSetting(_ key: String) -> ISupportEffects {
		var effects = ISupportEffects()

		if let token = ISupportToken(tokenName: key) {
			resetSetting(token, into: &effects)
		}

		return effects
	}

	/** Clears one token.

	 The outer switch is exhaustive on purpose: a token the session reads is a
	 token it has to be able to forget, so a case added to ``ISupportToken``
	 does not compile until it is put in one of these four groups. */
	private func resetSetting(_ token: ISupportToken, into effects: inout ISupportEffects) {
		switch token {
		case .awaylen, .channellen, .chathistory, .keylen, .kicklen, .linelen,
		     .maxtargets, .modes, .nicklen, .silence, .topiclen:
			resetCount(token)
		case .bot, .callerid, .casemapping, .chanmodes, .chantypes, .deaf,
		     .excepts, .invex, .prefix, .statusmsg:
			resetModeSetting(token)
		case .chanlimit, .clienttagdeny, .elist, .extban, .maxlist, .msgreftypes, .network, .targmax:
			resetCollection(token)
		case .monitor, .namesx, .safelist, .uhnames, .utf8only, .watch, .whox:
			resetAnnouncement(token, into: &effects)
		}
	}

	/// Puts a length or a count back to what the protocol assumes when no
	/// server has said otherwise.
	private func resetCount(_ token: ISupportToken) {
		switch token {
		case .awaylen:
			maximumAwayLength = 0
		case .channellen:
			maximumChannelNameLength = 0
		case .chathistory:
			chatHistoryMaximumLines = 0
		case .keylen:
			maximumKeyLength = 0
		case .kicklen:
			maximumKickLength = 0
		case .linelen:
			maximumLineLength = 0
		case .maxtargets:
			maximumTargets = 0
		case .modes:
			maximumModeCount = UInt(ProtocolLimits.maximumNodesPerModeCommand)
		case .nicklen:
			maximumNicknameLength = UInt(ProtocolLimits.defaultNicknameMaximumLength)
		case .silence:
			silenceSupported = false
			maximumSilenceEntries = 0
		case .topiclen:
			maximumTopicLength = 0
		default:
			break
		}
	}

	/// Puts a mode letter, or a table of them, back to the usual spelling.
	private func resetModeSetting(_ token: ISupportToken) {
		switch token {
		case .bot:
			botModeSymbol = nil
		case .callerid:
			callerIDModeSymbol = nil
		case .casemapping:
			caseMapping = .rfc1459
		case .chanmodes:
			advertisedChannelModeKinds = [:]
		case .chantypes:
			channelNamePrefixes = ["#"]
		case .deaf:
			deafModeSymbol = nil
		case .excepts:
			banExceptionModeSymbol = nil
		case .invex:
			inviteExceptionModeSymbol = nil
		case .prefix:
			userModePrefixPairs = defaultUserModePrefixPairs
		case .statusmsg:
			statusMessagePrefixCharacters = []
		default:
			break
		}
	}

	private func resetCollection(_ token: ISupportToken) {
		switch token {
		case .chanlimit:
			channelLimits = [:]
		case .clienttagdeny:
			clientTagDenyList = []
		case .elist:
			extendedListTokens = []
		case .extban:
			extendedBanPrefix = nil
			extendedBanTypes = []
		case .maxlist:
			maximumListEntries = [:]
		case .msgreftypes:
			chatHistorySupportsTimestamps = true
			chatHistorySupportsMessageIdentifiers = true
		case .network:
			networkName = nil
			networkNameFormatted = nil
		case .targmax:
			maximumTargetsByCommand = [:]
		default:
			break
		}
	}

	/** Takes back what a token announced by being there at all.

	 Four of them were the only evidence for a capability. Losing the token
	 loses the fact, which only the session can withdraw, so it is reported
	 rather than acted on. */
	private func resetAnnouncement(_ token: ISupportToken, into effects: inout ISupportEffects) {
		switch token {
		case .monitor:
			maximumMonitorEntries = 0
			effects.withdrawnCapabilities.insert(.monitorCommand)
		case .watch:
			maximumWatchEntries = 0
			effects.withdrawnCapabilities.insert(.watchCommand)
		case .namesx:
			effects.withdrawnCapabilities.insert(.multiPrefix)
		case .uhnames:
			effects.withdrawnCapabilities.insert(.userhostInNames)
		case .safelist:
			safeListSupported = false
		case .utf8only:
			utf8Only = false
		case .whox:
			whoxSupported = false
		default:
			break
		}
	}

	func removeCachedSetting(_ key: String) {
		for cachedKey in lastConfiguration.keys where cachedKey.caseInsensitiveCompare(key) == .orderedSame {
			lastConfiguration.removeValue(forKey: cachedKey)
		}
	}

	/** Reads one ISUPPORT line into the table.

	 Nothing here reaches the server or the capability state: what the tokens
	 ask for beyond their values comes back as ``ISupportEffects`` for the session
	 to apply. */
	@discardableResult
	func processConfigurationData(_ configurationData: String) -> ISupportEffects {
		var effects = ISupportEffects()
		let trimmed = configurationData.trimmingCharacters(in: .whitespacesAndNewlines)

		if trimmed.isEmpty {
			return effects
		}

		var configuration: [String: ISupportValue] = [:]
		let segments = LineParser.wireTokens(in: trimmed)

		for segment in segments {
			var segmentKey = segment
			var segmentValue: String?

			if let equalSignIndex = segment.firstIndex(of: "="), equalSignIndex != segment.startIndex {
				segmentKey = String(segment[..<equalSignIndex])
				segmentValue = ISupportTokenParser.unescapedValue(
					segment[segment.index(after: equalSignIndex)...]
				)

				if segmentValue?.isEmpty == true,
				   ISupportToken(tokenName: segmentKey)?.readsAnEmptyValueAsNone != true
				{
					segmentValue = nil
				}
			}

			if segmentKey.hasPrefix("-"), segmentKey.count > 1 {
				let negatedKey = String(segmentKey.dropFirst())

				if let token = ISupportToken(tokenName: negatedKey) {
					resetSetting(token, into: &effects)
				}

				removeCachedSetting(negatedKey)
				configuration.removeValue(forKey: negatedKey)

				continue
			}

			configuration[segmentKey] = segmentValue.map(ISupportValue.text) ?? .flag

			guard let token = ISupportToken(tokenName: segmentKey) else {
				continue
			}

			for change in ISupportChange.reading(token, value: segmentValue) {
				apply(change, into: &effects)
			}
		}

		if configuration.isEmpty == false {
			lastConfiguration = configuration
			hasReceivedConfiguration = true
		}

		return effects
	}

	func parseModes(_ modeString: String) -> [ModeInfo] {
		ModeParser.parse(modeString, channelModeKinds: channelModeKinds)
	}
}

// MARK: - Applying what a token says

private extension ISupport {
	/// Records one change read from a token, or reports it when only the
	/// session can act on it.
	func apply(_ change: ISupportChange, into effects: inout ISupportEffects) {
		switch change {
		case let .count(count, value):
			set(count, to: value)
		case let .modeSymbol(letter, symbol):
			set(letter, to: symbol)
		case let .feature(feature):
			enable(feature)
		case let .silenceSupported(maximumEntries):
			silenceSupported = true
			maximumSilenceEntries = maximumEntries ?? maximumSilenceEntries
		case let .caseMapping(mapping):
			caseMapping = mapping
		case let .channelModeKinds(kinds):
			advertisedChannelModeKinds = kinds
		case let .channelNamePrefixes(prefixes):
			channelNamePrefixes = prefixes
		case let .networkName(name):
			networkName = name
			networkNameFormatted = String(localized: .IRC.ircNetwork(name))
		case let .userModePrefixes(modeSymbols, characters):
			userModePrefixPairs = zip(modeSymbols, characters).map { (modeSymbol: $0, character: $1) }
		case let .statusMessagePrefixCharacters(characters):
			statusMessagePrefixCharacters = characters
		case let .channelLimits(limits):
			channelLimits = limits
		case let .clientTagDenyList(tags):
			clientTagDenyList = tags
		case let .chatHistoryReferences(timestamps, messageIdentifiers):
			chatHistorySupportsTimestamps = timestamps
			chatHistorySupportsMessageIdentifiers = messageIdentifiers
		case let .extendedListTokens(tokens):
			extendedListTokens = tokens
		case let .extendedBan(prefix, types):
			extendedBanPrefix = prefix
			extendedBanTypes = types
		case let .maximumListEntries(entries):
			maximumListEntries = entries
		case let .maximumTargetsByCommand(targets):
			maximumTargetsByCommand = targets
		case let .enablesCapability(capability):
			effects.enabledCapabilities.insert(capability)
		case let .legacyCapability(legacy):
			effects.legacyCapabilities.append(legacy)
		}
	}

	func set(_ count: ISupportChange.Count, to value: UInt) {
		switch count {
		case .awayLength: maximumAwayLength = value
		case .channelNameLength: maximumChannelNameLength = value
		case .chatHistoryLines: chatHistoryMaximumLines = value
		case .keyLength: maximumKeyLength = value
		case .kickLength: maximumKickLength = value
		case .lineLength: maximumLineLength = value
		case .targets: maximumTargets = value
		case .modes: maximumModeCount = value
		case .monitorEntries: maximumMonitorEntries = value
		case .watchEntries: maximumWatchEntries = value
		case .nicknameLength: maximumNicknameLength = value
		case .topicLength: maximumTopicLength = value
		}
	}

	func set(_ letter: ISupportChange.ModeLetter, to symbol: String) {
		switch letter {
		case .bot: botModeSymbol = symbol
		case .callerID: callerIDModeSymbol = symbol
		case .deaf: deafModeSymbol = symbol
		case .banException: banExceptionModeSymbol = symbol
		case .inviteException: inviteExceptionModeSymbol = symbol
		}
	}

	func enable(_ feature: ISupportChange.Feature) {
		switch feature {
		case .safeList: safeListSupported = true
		case .utf8Only: utf8Only = true
		case .whox: whoxSupported = true
		}
	}
}
