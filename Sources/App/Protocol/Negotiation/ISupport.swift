// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

enum ISupportListKind: UInt, Sendable {
	case ban = 0
	case banException = 1
	case inviteException = 2
	case quiet = 3
}

nonisolated enum ISupportCaseMapping: UInt, Sendable {
	case rfc1459 = 0
	case strictRFC1459 = 1
	case ascii = 2
	/// RFC 7613 §3.3 `UsernameCaseMapped`: Unicode case folding and NFC, with
	/// none of the ASCII bracket-to-brace equivalences the RFC 1459 mappings
	/// inherited from Scandinavian keyboards.
	case rfc7613 = 3
}

/// One token of an ISUPPORT line as the server sent it.
///
/// A token is either `KEY=value` or a bare `KEY` standing for a feature the
/// server merely announces. The most recent line is kept verbatim so the
/// numeric handler can spell it back out as the server sent it.
enum ISupportValue: Sendable, Equatable {
	case flag
	case text(String)
}

/** A token the session reads out of an ISUPPORT line.

 The raw value is the token name as the server writes it, upper-cased. Only a
 token with a case here is read at all, and every one of them is cleared by
 `reset` — the reset switch is exhaustive, so a case added below is a token the
 session both reads and forgets.
 */
nonisolated enum ISupportToken: String, CaseIterable, Sendable {
	case awaylen = "AWAYLEN"
	case bot = "BOT"
	case callerid = "CALLERID"
	case casemapping = "CASEMAPPING"
	case chanlimit = "CHANLIMIT"
	case chanmodes = "CHANMODES"
	case channellen = "CHANNELLEN"
	case chantypes = "CHANTYPES"
	case chathistory = "CHATHISTORY"
	case clienttagdeny = "CLIENTTAGDENY"
	case deaf = "DEAF"
	case elist = "ELIST"
	case excepts = "EXCEPTS"
	case extban = "EXTBAN"
	case invex = "INVEX"
	case keylen = "KEYLEN"
	case kicklen = "KICKLEN"
	case linelen = "LINELEN"
	case maxlist = "MAXLIST"
	case maxtargets = "MAXTARGETS"
	case modes = "MODES"
	case monitor = "MONITOR"
	case namesx = "NAMESX"
	case network = "NETWORK"
	case nicklen = "NICKLEN"
	case prefix = "PREFIX"
	case safelist = "SAFELIST"
	case silence = "SILENCE"
	case statusmsg = "STATUSMSG"
	case targmax = "TARGMAX"
	case topiclen = "TOPICLEN"
	case uhnames = "UHNAMES"
	case utf8only = "UTF8ONLY"
	case watch = "WATCH"
	case whox = "WHOX"

	/// Matches the token however the server capitalised it, and under the
	/// draft name a server may still advertise it by.
	init?(tokenName: String) {
		let normalized = tokenName.uppercased()

		if normalized == Self.draftChatHistoryName {
			self = .chathistory

			return
		}

		self.init(rawValue: normalized)
	}

	/** Whether an explicitly empty value means "the server has none of these".

	 modern.ircdocs.horse gives an empty value that meaning for the tokens whose
	 value is a list of characters. For every other token an empty value says no
	 more than the bare token does. */
	var readsAnEmptyValueAsNone: Bool {
		switch self {
		case .chantypes, .prefix, .statusmsg: true
		default: false
		}
	}

	private static let draftChatHistoryName = "DRAFT/CHATHISTORY"
}

/// The two prefix modes every server is assumed to have until it says
/// otherwise.
private nonisolated let defaultUserModePrefixPairs: [(modeSymbol: String, character: String)] = [
	(modeSymbol: "o", character: "@"), (modeSymbol: "v", character: "+"),
]

private nonisolated let defaultChannelModeKinds: [Character: ChannelModeKind] = [
	"o": .userPrefix, "v": .userPrefix,
]

/** What an ISUPPORT line asks the session to do, beyond the values it recorded.

 ``ISupport`` reads tokens and does nothing else: it writes no line and touches
 no capability state, so it needs no way back to the session that owns it. A
 token that means more than the value it carries says so here instead, and the
 session applies it. */
nonisolated struct ISupportEffects: Sendable, Equatable {
	/** A capability an ISUPPORT token stands in for on a server that never
	 offered it through `CAP`, and the pre-CAP line that turns it on. */
	nonisolated struct LegacyCapability: Sendable, Equatable {
		let capability: CapabilitySet
		let command: String
	}

	/// Capabilities the tokens prove the server has.
	var enabledCapabilities: CapabilitySet = []
	/// Capability facts the tokens that went away took with them.
	var withdrawnCapabilities: CapabilitySet = []
	/// Legacy capabilities to turn on, in the order their tokens arrived.
	var legacyCapabilities: [LegacyCapability] = []
}

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
		case .chanlimit, .clienttagdeny, .elist, .extban, .maxlist, .network, .targmax:
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

			if let segmentValue {
				processValueSegment(token, segmentValue: segmentValue)
			}

			processFlagSegment(token, segmentValue: segmentValue, into: &effects)
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

// MARK: - Reading a token's value

private extension ISupport {
	/** Reads the value half of a token.

	 A token whose value is a count is read as one first, so that a count the
	 token does not take (`NETWORK=42`) still falls through to the text reading
	 that does. */
	func processValueSegment(_ token: ISupportToken, segmentValue value: String) {
		if let count = positiveInteger(from: value), processCountValue(token, count: count) {
			return
		}

		switch token {
		case .casemapping:
			parseCaseMapping(value)
		case .chanmodes:
			/* A re-sent CHANMODES replaces the table rather than adding to it,
			 so a shorter one does not leave the modes it dropped behind. */
			advertisedChannelModeKinds = ISupportTokenParser.channelModeKinds(from: value, merging: [:])
		case .chantypes:
			/* An empty CHANTYPES is the server saying it supports no channel
			 types at all, which is not the same as it saying nothing. */
			channelNamePrefixes = value.map(String.init)
		case .network:
			networkName = value
			networkNameFormatted = String(localized: .IRC.ircNetwork(value))
		case .prefix:
			parseUserModeSymbols(value)
		case .statusmsg:
			statusMessagePrefixCharacters = value.map(String.init)
		case .chanlimit:
			channelLimits = ISupportTokenParser.channelLimits(from: value)
		case .clienttagdeny:
			clientTagDenyList = value.components(separatedBy: ",")
		case .elist:
			extendedListTokens = value.uppercased().map(String.init)
		case .extban:
			let configuration = ISupportTokenParser.extendedBanConfiguration(from: value)
			extendedBanPrefix = configuration.prefix
			extendedBanTypes = configuration.types
		case .maxlist:
			maximumListEntries = ISupportTokenParser.maximumListEntries(from: value)
		case .targmax:
			maximumTargetsByCommand = ISupportTokenParser.maximumTargets(from: value)
		default:
			break
		}
	}

	/// Whether `token` is one whose value is a count, and takes this one.
	func processCountValue(_ token: ISupportToken, count: UInt) -> Bool {
		switch token {
		case .awaylen:
			maximumAwayLength = count
		case .channellen:
			maximumChannelNameLength = count
		case .chathistory:
			chatHistoryMaximumLines = count
		case .keylen:
			maximumKeyLength = count
		case .kicklen:
			maximumKickLength = count
		case .linelen:
			maximumLineLength = min(count, UInt(ProtocolLimits.maximumServerLineLength))
		case .maxtargets:
			maximumTargets = count
		case .modes:
			maximumModeCount = count
		/* The count is the whole point of these two: past it the server answers
		 ERR_MONLISTFULL or ERR_TOOMANYWATCH and the tail of the list is simply
		 not tracked. The flag half of the token still enables the capability. */
		case .monitor:
			maximumMonitorEntries = count
		case .watch:
			maximumWatchEntries = count
		case .nicklen:
			maximumNicknameLength = count
		case .topiclen:
			maximumTopicLength = count
		default:
			return false
		}

		return true
	}

	/** A token's value as a count.

	 `NSString.integerValue` used to do this, which accepts trailing junk
	 (`NICKLEN=50abc` read as 50) and saturates at `Int.max` on overflow instead
	 of rejecting, which is how `LINELEN=99999999999999999999` turned into a
	 line budget that never split anything. */
	func positiveInteger(from value: String) -> UInt? {
		guard let parsedValue = UInt(value), parsedValue > 0 else {
			return nil
		}

		return parsedValue
	}

	func parseCaseMapping(_ caseMapping: String) {
		if caseMapping.caseInsensitiveCompare("ascii") == .orderedSame {
			self.caseMapping = .ascii
		} else if caseMapping.caseInsensitiveCompare("strict-rfc1459") == .orderedSame {
			self.caseMapping = .strictRFC1459
		} else if caseMapping.caseInsensitiveCompare("rfc8265") == .orderedSame
			|| caseMapping.caseInsensitiveCompare("rfc7613") == .orderedSame
		{
			/* RFC 8265 obsoletes RFC 7613 and keeps its casefold; servers
			 advertise either name for the same mapping. */
			self.caseMapping = .rfc7613
		} else {
			self.caseMapping = .rfc1459
		}
	}

	func parseUserModeSymbols(_ modeString: String) {
		/* An empty PREFIX is the server saying it has no membership prefixes,
		 which has to clear the assumed op/voice pair rather than leave it. */
		guard modeString.isEmpty == false else {
			userModePrefixPairs = []
			return
		}

		guard let configuration = ISupportTokenParser.userPrefixConfiguration(from: modeString) else {
			return
		}

		userModePrefixPairs = zip(configuration.modeSymbols, configuration.characters)
			.map { (modeSymbol: $0, character: $1) }
	}
}

// MARK: - Reading a token as an announcement

private extension ISupport {
	/// Reads what a token says by being present at all, whatever value it
	/// carried.
	func processFlagSegment(
		_ token: ISupportToken,
		segmentValue value: String?,
		into effects: inout ISupportEffects
	) {
		switch token {
		// Mode letters, which a server may name or leave at the usual one.
		case .bot:
			if value?.isModeSymbol == true {
				botModeSymbol = value
			}
		case .callerid:
			callerIDModeSymbol = validatedModeSymbol(value, fallback: "g")
		case .deaf:
			deafModeSymbol = validatedModeSymbol(value, fallback: "D")
		case .excepts:
			banExceptionModeSymbol = validatedModeSymbol(value, fallback: "e")
		case .invex:
			inviteExceptionModeSymbol = validatedModeSymbol(value, fallback: "I")
		// Capabilities the token is the only evidence for.
		case .monitor:
			effects.enabledCapabilities.insert(.monitorCommand)
		case .watch:
			effects.enabledCapabilities.insert(.watchCommand)
		case .namesx:
			effects.legacyCapabilities.append(
				ISupportEffects.LegacyCapability(capability: .multiPrefix, command: "PROTOCTL NAMESX")
			)
		case .uhnames:
			effects.legacyCapabilities.append(
				ISupportEffects.LegacyCapability(capability: .userhostInNames, command: "PROTOCTL UHNAMES")
			)
		// Plain announcements.
		case .safelist:
			safeListSupported = true
		case .silence:
			silenceSupported = true

			if let value, let limit = positiveInteger(from: value) {
				maximumSilenceEntries = limit
			}
		case .utf8only:
			utf8Only = true
		case .whox:
			whoxSupported = true
		default:
			break
		}
	}

	func validatedModeSymbol(_ value: String?, fallback: String) -> String {
		guard let value, value.isModeSymbol else {
			return fallback
		}

		return value
	}
}
