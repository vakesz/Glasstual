// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Synchronization

enum ISupportListType: UInt, Sendable {
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

nonisolated enum ISupportUserModes {
	static let highestPrefixRank: UInt = 100
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

/** A token the client reads out of an ISUPPORT line.

 The raw value is the token name as the server writes it, upper-cased. Only a
 token with a case here is read at all, and every one of them is cleared by
 `reset`, so a case added below is a token the client both reads and forgets.
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

/** The ISUPPORT values a channel member needs in order to rank and mark itself.
 Members are ranked, compared and rendered off the main actor, so the client
 republishes these as a value rather than exposing the live table. */
nonisolated struct UserPrefixTable: Sendable {
	/// Mode symbols in the order the server ranked them, highest first.
	var modeSymbols = ["o", "v"]
	/// The prefix character for the mode symbol at the same index.
	var prefixCharacters = ["@", "+"]
	var caseMapping = ISupportCaseMapping.rfc1459

	func userPrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let index = modeSymbols.firstIndex(of: modeSymbol),
		      index < prefixCharacters.count
		else {
			return nil
		}

		return prefixCharacters[index]
	}

	func rank(forModeSymbol modeSymbol: String) -> UInt {
		guard let index = modeSymbols.firstIndex(of: modeSymbol) else {
			return 0
		}

		// A server may advertise more prefix modes than the rank ceiling; the
		// lowest-ranked ones all collapse to rank 1 rather than underflowing.
		guard UInt(index) < ISupportUserModes.highestPrefixRank else {
			return 1
		}

		return ISupportUserModes.highestPrefixRank - UInt(index)
	}

	func casefold(_ string: String) -> String {
		ISupportTokenParser.casefold(string, caseMapping: caseMapping)
	}
}

final class ISupport {
	private(set) weak var client: Client?
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
			publishUserPrefixTable()
		}
	}

	private(set) var banExceptionModeSymbol: String?
	private(set) var inviteExceptionModeSymbol: String?
	private(set) var botModeSymbol: String?
	private(set) var callerIDModeSymbol: String?
	private(set) var deafModeSymbol: String?
	private(set) var extendedBanPrefix: String?
	private(set) var networkName: String?
	private(set) var networkNameFormatted: String?
	private(set) var caseMapping: ISupportCaseMapping = .rfc1459 {
		didSet { publishUserPrefixTable() }
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

	/// Republishes the table members are stamped with when the list edits one.
	private func publishUserPrefixTable() {
		let table = UserPrefixTable(
			modeSymbols: userModePrefixPairs.map(\.modeSymbol),
			prefixCharacters: userModePrefixPairs.map(\.character),
			caseMapping: caseMapping
		)
		client?.publishUserPrefixes(table)
	}

	/** The most recent 005 line, its values unescaped, kept so the numeric
	 handler can spell back out what the server just said.

	 Only the newest line is ever read, and a server may send 005 for as long as
	 it stays connected, so the earlier ones are not kept. */
	private var lastConfiguration: [String: ISupportValue] = [:]
	private var hasReceivedConfiguration = false

	init(client: Client? = nil) {
		self.client = client
		prepareInitialState()
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

	func reset() {
		reset(withdrawingCapabilityFacts: true)
	}

	/** Clears every advertised value.

	 `withdrawingCapabilityFacts` is what separates a reconnect from a first
	 look: a reconnect really has lost the `MONITOR`, `WATCH`, `NAMESX` and
	 `UHNAMES` the client recorded as capability facts, while a brand new
	 instance has nothing to withdraw -- see ``prepareInitialState()``. */
	private func reset(withdrawingCapabilityFacts: Bool) {
		lastConfiguration = [:]
		hasReceivedConfiguration = false
		serverAddress = nil
		userModePrefixPairs = defaultUserModePrefixPairs

		for token in ISupportToken.allCases {
			resetSetting(token, withdrawingCapabilityFacts: withdrawingCapabilityFacts)
		}
	}

	func resetSetting(_ key: String) {
		guard let token = ISupportToken(tokenName: key) else { return }

		resetSetting(token, withdrawingCapabilityFacts: true)
	}

	private func resetSetting(_ token: ISupportToken, withdrawingCapabilityFacts: Bool) {
		if resetLengthSetting(token) {
			return
		}

		if resetModeSetting(token) {
			return
		}

		if resetCollectionSetting(token) {
			return
		}

		resetFeatureSetting(token, withdrawingCapabilityFacts: withdrawingCapabilityFacts)
	}

	private func resetLengthSetting(_ token: ISupportToken) -> Bool {
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
			return false
		}

		return true
	}

	private func resetModeSetting(_ token: ISupportToken) -> Bool {
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
			return false
		}

		return true
	}

	private func resetCollectionSetting(_ token: ISupportToken) -> Bool {
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
			return false
		}

		return true
	}

	private func resetFeatureSetting(_ token: ISupportToken, withdrawingCapabilityFacts: Bool) {
		/// The fact this token stands in for, withdrawn only when the token it
		/// came from is being taken away rather than merely cleared.
		func withdraw(_ capability: CapabilitySet) {
			guard withdrawingCapabilityFacts else { return }
			client?.removeCapabilityFacts(capability)
		}

		switch token {
		case .monitor:
			maximumMonitorEntries = 0
			withdraw(.monitorCommand)
		case .watch:
			maximumWatchEntries = 0
			withdraw(.watchCommand)
		case .namesx:
			withdraw(.multiPrefix)
		case .uhnames:
			withdraw(.userhostInNames)
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

	func processConfigurationData(_ configurationData: String) {
		let trimmed = configurationData.trimmingCharacters(in: .whitespacesAndNewlines)

		if trimmed.isEmpty {
			return
		}

		let client = client
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

				resetSetting(negatedKey)
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

			processFlagSegment(token, segmentValue: segmentValue, client: client)
		}

		if configuration.isEmpty == false {
			lastConfiguration = configuration
			hasReceivedConfiguration = true
		}
	}

	func channelLimit(forChannelNamed channel: String) -> UInt {
		if channel.isEmpty {
			return 0
		}

		guard let prefix = channel.first else {
			return 0
		}

		return channelLimits[prefix] ?? 0
	}

	/** How many targets the server said `command` takes on one line.

	 Zero means the server said nothing usable: it named no `TARGMAX` entry for
	 the command, or named one with an empty limit, and sent no `MAXTARGETS`
	 either. The empty `TARGMAX` limit does mean "no limit" in the specification,
	 but it arrives as the same zero as silence and is read the same
	 conservative way, because the two are worth the same to a client: see
	 ``groupsMultipleTargets(forCommand:)`` for what the client then does.
	 */
	func maximumTargets(forCommand command: String) -> UInt {
		if let limit = maximumTargetsByCommand[command.uppercased()] {
			return limit
		}

		return maximumTargets
	}

	/** Whether several targets may ride on one `command`.

	 Only an advertised limit above one earns a comma-separated target list. A
	 server that advertised nothing (zero) gets one target per line, the same as
	 one that said `TARGMAX=PRIVMSG:1`: a server that does not take a list
	 answers `ERR_TOOMANYTARGETS` or silently drops every target after the
	 first, and the user has no way to tell that the message never arrived. One
	 line per target always arrives, and costs only lines.

	 `JOIN` does not come through here. A comma-separated channel list is core
	 `JOIN` syntax rather than an extension, so ``JoinBatching`` fills a line
	 whether or not the server advertised a `TARGMAX` for it.
	 */
	func groupsMultipleTargets(forCommand command: String) -> Bool {
		maximumTargets(forCommand: command) > 1
	}

	func maximumListEntries(forModeSymbol modeSymbol: ChannelModeSymbol) -> UInt {
		maximumListEntries[modeSymbol.character] ?? 0
	}

	func extendedListSupportsToken(_ token: String) -> Bool {
		extendedListTokens.contains(token.uppercased())
	}

	func isClientTagDenied(_ tagName: String) -> Bool {
		ISupportTokenParser.isClientTag(tagName, deniedBy: clientTagDenyList)
	}

	func descriptionForExtendedBanMask(_ mask: String) -> String? {
		if extendedBanTypes.isEmpty {
			return nil
		}

		var body = mask

		if let prefix = extendedBanPrefix {
			if mask.hasPrefix(prefix) == false {
				return nil
			}

			body = String(mask.dropFirst(prefix.count))
		}

		var negated = false

		if extendedBanPrefix != "~", body.hasPrefix("~"), body.count > 1 {
			negated = true
			body = String(body.dropFirst())
		}

		if body.isEmpty {
			return nil
		}

		let type = String(body.prefix(1))

		if extendedBanTypes.contains(type) == false {
			return nil
		}

		var argument: String?

		if body.count > 2, body[body.index(body.startIndex, offsetBy: 1)] == ":" {
			argument = String(body.dropFirst(2))
		} else if body.count > 1 || extendedBanPrefix == nil {
			return nil
		}

		let description = Self.localizedDescription(forExtendedBanType: type, argument: argument)

		if negated {
			return String(localized: .IRC.everyoneExcept(description))
		}

		return description
	}

	static func localizedDescription(forExtendedBanType type: String, argument: String?) -> String {
		ExtendedBanKind.describing(type: type, argument: argument)
	}

	func stringValue(forConfiguration configuration: [String: ISupportValue]) -> String? {
		if configuration.isEmpty {
			return nil
		}

		var stringValue = ""

		for key in configuration.keys.sorted() {
			switch configuration[key] {
			case let .text(value):
				stringValue.append("\u{02}\(key)\u{02}=\(value) ")
			case .flag, nil:
				stringValue.append("\u{02}\(key) \u{02}")
			}
		}

		return stringValue
	}

	func parseModes(_ modeString: String) -> [ModeInfo] {
		ModeParser.parse(modeString, channelModeKinds: channelModeKinds)
	}

	func casefoldString(_ string: String) -> String {
		ISupportTokenParser.casefold(string, caseMapping: caseMapping)
	}

	/// Whether a mode letter carries a parameter.
	///
	/// Through the same RFC 1459 fallback ``ModeParser/parse(_:channelModeKinds:)``
	/// applies, so that a `MODE` arriving before 005 is answered the same way
	/// whether it is being parsed or being asked about: without it `+b` read as a
	/// bare flag here and as a list mode there.
	func modeHasParameter(_ modeSymbol: String, whenModeIsSet: Bool) -> Bool {
		guard let symbol = modeSymbol.first, modeSymbol.count == 1 else {
			return false
		}

		let modeKinds = ModeParser.effectiveChannelModeKinds(channelModeKinds)
		let policy = modeKinds[symbol]?.parameterPolicy ?? .never

		return policy.requiresParameter(whenModeIsSet: whenModeIsSet)
	}

	func userPrefix(forModeSymbol modeSymbol: String) -> String? {
		userModePrefixPairs.first { $0.modeSymbol == modeSymbol }?.character
	}

	func modeSymbolIsUserPrefix(_ modeSymbol: String) -> Bool {
		userPrefix(forModeSymbol: modeSymbol) != nil
	}

	func modeSymbol(forUserPrefix character: String) -> String? {
		userModePrefixPairs.first { $0.character == character }?.modeSymbol
	}

	func characterIsUserPrefix(_ character: String) -> Bool {
		modeSymbol(forUserPrefix: character) != nil
	}

	func rankForUserPrefix(withMode modeSymbol: String) -> UInt {
		guard let modeSymbolIndex = userModePrefixPairs.firstIndex(where: { $0.modeSymbol == modeSymbol })
		else {
			return 0
		}

		// A server may advertise more prefix modes than the rank ceiling; the
		// lowest-ranked ones all collapse to rank 1 rather than underflowing.
		guard UInt(modeSymbolIndex) < ISupportUserModes.highestPrefixRank else {
			return 1
		}

		return ISupportUserModes.highestPrefixRank - UInt(modeSymbolIndex)
	}

	func extractStatusMessagePrefix(fromChannelNamed channel: String) -> String {
		extractCharacters(statusMessagePrefixCharacters, fromChannelNamed: channel)
	}

	func isListSupported(_ listType: ISupportListType) -> Bool {
		modeSymbol(forList: listType) != nil
	}

	func modeSymbol(forList listType: ISupportListType) -> String? {
		switch listType {
		case .ban:
			return "b"
		case .banException:
			return banExceptionModeSymbol
		case .inviteException:
			return inviteExceptionModeSymbol
		case .quiet:
			if modeSymbolIsUserPrefix("q") {
				return nil
			}

			return "q"
		}
	}

	func statusMessagePrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let character = userPrefix(forModeSymbol: modeSymbol) else {
			return nil
		}

		if statusMessagePrefixCharacters.contains(character) == false {
			return nil
		}

		return character
	}
}

private extension ISupport {
	/** The state a connection starts in.

	 No capability fact is withdrawn on the way. `Client.supportInfo` is
	 `lazy`, so the first read of it can come long after ISUPPORT-derived facts
	 were recorded -- `enableCapability(.watchCommand)` reads it on its way to
	 asking the server about the tracked peers -- and a construction-time reset
	 that called back into the client withdrew the very fact that had just been
	 set, leaving `WATCH` and `MONITOR` disabled on servers that offer them. A
	 new instance has nothing to withdraw. */
	func prepareInitialState() {
		reset(withdrawingCapabilityFacts: false)
	}

	func processValueSegment(_ token: ISupportToken, segmentValue: String) {
		if processPositiveLengthValue(token, value: segmentValue) {
			return
		}

		if processChannelValue(token, value: segmentValue) {
			return
		}

		processCollectionValue(token, value: segmentValue)
	}

	func processPositiveLengthValue(_ token: ISupportToken, value: String) -> Bool {
		guard let parsedValue = positiveInteger(from: value) else {
			return false
		}

		switch token {
		case .awaylen:
			maximumAwayLength = parsedValue
		case .channellen:
			maximumChannelNameLength = parsedValue
		case .chathistory:
			chatHistoryMaximumLines = parsedValue
		case .keylen:
			maximumKeyLength = parsedValue
		case .kicklen:
			maximumKickLength = parsedValue
		case .linelen:
			maximumLineLength = min(parsedValue, UInt(ProtocolLimits.maximumServerLineLength))
		case .maxtargets:
			maximumTargets = parsedValue
		case .modes:
			maximumModeCount = parsedValue
		/* The count is the whole point of these two: past it the server answers
		 ERR_MONLISTFULL or ERR_TOOMANYWATCH and the tail of the list is simply
		 not tracked. The flag half of the token still enables the capability in
		 `processCapabilityFlag`. */
		case .monitor:
			maximumMonitorEntries = parsedValue
		case .watch:
			maximumWatchEntries = parsedValue
		case .nicklen:
			maximumNicknameLength = parsedValue
		case .topiclen:
			maximumTopicLength = parsedValue
		default:
			return false
		}

		return true
	}

	func processChannelValue(_ token: ISupportToken, value: String) -> Bool {
		switch token {
		case .casemapping:
			parseCaseMapping(value)
		case .chanmodes:
			/* A re-sent CHANMODES replaces the table rather than adding to it,
			 so a shorter one does not leave the modes it dropped behind. */
			advertisedChannelModeKinds = ISupportTokenParser.channelModeKinds(from: value, merging: [:])
		case .chantypes:
			updateChannelNamePrefixes(from: value)
		case .network:
			networkName = value
			networkNameFormatted = String(localized: .IRC.ircNetwork(value))
		case .prefix:
			parseUserModeSymbols(value)
		case .statusmsg:
			statusMessagePrefixCharacters = value.map(String.init)
		default:
			return false
		}

		return true
	}

	func processCollectionValue(_ token: ISupportToken, value: String) {
		switch token {
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

	/// An empty `CHANTYPES` is the server saying it supports no channel types
	/// at all, which is not the same as it saying nothing.
	func updateChannelNamePrefixes(from value: String) {
		channelNamePrefixes = value.map(String.init)
	}

	func processFlagSegment(_ token: ISupportToken, segmentValue: String?, client: Client?) {
		if processModeFlag(token, value: segmentValue) {
			return
		}

		if processCapabilityFlag(token, client: client) {
			return
		}

		processAvailabilityFlag(token, value: segmentValue)
	}

	func processModeFlag(_ token: ISupportToken, value: String?) -> Bool {
		switch token {
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
		default:
			return false
		}

		return true
	}

	func validatedModeSymbol(_ value: String?, fallback: String) -> String {
		guard let value, value.isModeSymbol else {
			return fallback
		}

		return value
	}

	func processCapabilityFlag(_ token: ISupportToken, client: Client?) -> Bool {
		switch token {
		case .monitor:
			client?.enableCapability(.monitorCommand)
		case .namesx:
			enableLegacyCapability(.multiPrefix, command: "PROTOCTL NAMESX", on: client)
		case .uhnames:
			enableLegacyCapability(.userhostInNames, command: "PROTOCTL UHNAMES", on: client)
		case .watch:
			client?.enableCapability(.watchCommand)
		default:
			return false
		}

		return true
	}

	func enableLegacyCapability(
		_ capability: CapabilitySet,
		command: String,
		on client: Client?
	) {
		guard let client, client.capabilityFacts.contains(capability) == false else {
			return
		}

		client.sendLine(command)
		client.addCapabilityFacts(capability)
	}

	func processAvailabilityFlag(_ token: ISupportToken, value: String?) {
		switch token {
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

	func extractCharacters(_ characters: [String], fromChannelNamed channel: String) -> String {
		if channel.count < 2 {
			return ""
		}

		for character in characters where channel.hasPrefix(character) {
			let nextCharacter = String(channel.dropFirst().prefix(1))

			if channelNamePrefixes.contains(nextCharacter) {
				return character
			}
		}

		return ""
	}
}
