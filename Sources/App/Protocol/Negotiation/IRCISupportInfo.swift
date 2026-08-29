/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
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
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Synchronization

public enum IRCISupportInfoListType: UInt, Sendable {
	case ban = 0
	case banException = 1
	case inviteException = 2
	case quiet = 3
}

public nonisolated enum IRCISupportInfoCaseMapping: UInt, Sendable { // nonisolated: value
	case rfc1459 = 0
	case strictRFC1459 = 1
	case ascii = 2
	/// RFC 7613 §3.3 `UsernameCaseMapped`: Unicode case folding and NFC, with
	/// none of the ASCII bracket-to-brace equivalences the RFC 1459 mappings
	/// inherited from Scandinavian keyboards.
	case rfc7613 = 3
}

nonisolated enum IRCISupportUserModes { // nonisolated: value
	static let highestPrefixRank: UInt = 100
}

/// One token of an ISUPPORT line as the server sent it.
///
/// A token is either `KEY=value` or a bare `KEY` standing for a feature the
/// server merely announces. The cache keeps them verbatim so the raw-traffic
/// view can replay the line the server actually sent.
enum ISupportValue: Sendable, Equatable {
	case flag
	case text(String)
}

/// The two prefix modes every server is assumed to have until it says
/// otherwise.
private nonisolated let defaultUserModePrefixPairs: [(modeSymbol: String, character: String)] = [ // nonisolated: let
	(modeSymbol: "o", character: "@"), (modeSymbol: "v", character: "+"),
]

private nonisolated let defaultChannelModeKinds: [Character: ChannelModeKind] = [ // nonisolated: let
	"o": .userPrefix, "v": .userPrefix,
]

/** The ISUPPORT values a channel member needs in order to rank and mark itself.
 Members are ranked, compared and rendered off the main actor, so the client
 republishes these as a value rather than exposing the live table. */
nonisolated struct IRCUserPrefixTable: Sendable { // nonisolated: value
	/// Mode symbols in the order the server ranked them, highest first.
	var modeSymbols = ["o", "v"]
	/// The prefix character for the mode symbol at the same index.
	var prefixCharacters = ["@", "+"]
	var caseMapping = IRCISupportInfoCaseMapping.rfc1459

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
		guard UInt(index) < IRCISupportUserModes.highestPrefixRank else {
			return 1
		}

		return IRCISupportUserModes.highestPrefixRank - UInt(index)
	}

	func casefold(_ string: String) -> String {
		ISupportTokenParser.casefold(string, caseMapping: caseMapping)
	}
}

public class IRCISupportInfo: NSObject {
	public private(set) weak var client: IRCClient?
	public internal(set) var serverAddress: String?
	public private(set) var maximumAwayLength: UInt = 0
	public private(set) var maximumChannelNameLength: UInt = 0
	public private(set) var maximumKeyLength: UInt = 0
	public private(set) var maximumKickLength: UInt = 0
	public private(set) var maximumNicknameLength: UInt = 0
	public private(set) var maximumTopicLength: UInt = 0
	public private(set) var maximumModeCount: UInt = 0
	public private(set) var maximumLineLength: UInt = 0
	public private(set) var maximumTargets: UInt = 0
	public private(set) var maximumSilenceEntries: UInt = 0
	public private(set) var chatHistoryMaximumLines: UInt = 0
	public private(set) var silenceSupported = false
	public private(set) var safeListSupported = false
	public private(set) var whoxSupported = false
	public private(set) var utf8Only = false
	public private(set) var channelNamePrefixes: [String] = ["#"]
	public private(set) var statusMessageModeSymbols: [String] = []
	public private(set) var extendedBanTypes: [String] = []
	public private(set) var extendedListTokens: [String] = []
	public private(set) var clientTagDenyList: [String] = []
	/// What class the server put each channel mode in, and therefore whether
	/// the mode carries a parameter.
	public private(set) var channelModeKinds: [Character: ChannelModeKind] = defaultChannelModeKinds
	/// `CHANLIMIT`, keyed by channel prefix.
	public private(set) var channelLimits: [Character: UInt] = [:]
	/// `MAXLIST`, keyed by list mode.
	public private(set) var maximumListEntries: [Character: UInt] = [:]
	/// `TARGMAX`, keyed by uppercased command name.
	public private(set) var maximumTargetsByCommand: [String: UInt] = [:]
	/// Mode symbol / prefix character pairs from ISUPPORT `PREFIX=`, stored as
	/// pairs so the two halves can never disagree in length.
	private(set) var userModePrefixPairs = defaultUserModePrefixPairs {
		didSet { publishUserPrefixTable() }
	}

	public private(set) var banExceptionModeSymbol: String?
	public private(set) var inviteExceptionModeSymbol: String?
	public private(set) var botModeSymbol: String?
	public private(set) var callerIDModeSymbol: String?
	public private(set) var deafModeSymbol: String?
	public private(set) var extendedBanPrefix: String?
	public private(set) var networkName: String?
	public private(set) var networkNameFormatted: String?
	public private(set) var caseMapping: IRCISupportInfoCaseMapping = .rfc1459 {
		didSet { publishUserPrefixTable() }
	}

	/// Republishes the values channel members read off the main actor.
	private func publishUserPrefixTable() {
		let table = IRCUserPrefixTable(
			modeSymbols: userModePrefixPairs.map(\.modeSymbol),
			prefixCharacters: userModePrefixPairs.map(\.character),
			caseMapping: caseMapping
		)
		client?.userPrefixes.withLock { $0 = table }
	}

	private var cachedConfiguration: [[String: ISupportValue]] = []

	override public init() {
		client = nil
		super.init()
		prepareInitialState()
	}

	public init(client: IRCClient?) {
		self.client = client
		super.init()
		prepareInitialState()
	}

	public var configurationReceived: Bool {
		cachedConfiguration.isEmpty == false
	}

	public var stringValueForLastUpdate: String? {
		guard let configuration = cachedConfiguration.last else {
			return nil
		}

		return stringValue(forConfiguration: configuration)
	}

	public func reset() {
		cachedConfiguration = []
		serverAddress = nil
		userModePrefixPairs = defaultUserModePrefixPairs
		channelModeKinds = defaultChannelModeKinds

		for key in Self.resettableSettings() {
			resetSetting(key)
		}
	}

	public static func resettableSettings() -> [String] {
		[
			"AWAYLEN", "BOT", "CALLERID", "CASEMAPPING", "CHANLIMIT", "CHANNELLEN",
			"CHANTYPES", "CHATHISTORY", "CLIENTTAGDENY", "DEAF", "ELIST", "EXCEPTS",
			"EXTBAN", "INVEX", "KEYLEN", "KICKLEN", "LINELEN", "MAXLIST",
			"MAXTARGETS", "MODES", "NETWORK", "NICKLEN", "PREFIX", "SAFELIST", "SILENCE",
			"STATUSMSG", "TARGMAX", "TOPICLEN", "UTF8ONLY", "WHOX",
		]
	}

	public func resetSetting(_ key: String) {
		let normalizedKey = key.uppercased()

		if resetLengthSetting(normalizedKey) {
			return
		}

		if resetModeSetting(normalizedKey) {
			return
		}

		if resetCollectionSetting(normalizedKey) {
			return
		}

		resetFeatureSetting(normalizedKey)
	}

	private func resetLengthSetting(_ key: String) -> Bool {
		switch key {
		case "AWAYLEN":
			maximumAwayLength = 0
		case "CHANNELLEN":
			maximumChannelNameLength = 0
		case "CHATHISTORY", "DRAFT/CHATHISTORY":
			chatHistoryMaximumLines = 0
		case "KEYLEN":
			maximumKeyLength = 0
		case "KICKLEN":
			maximumKickLength = 0
		case "LINELEN":
			maximumLineLength = 0
		case "MAXTARGETS":
			maximumTargets = 0
		case "MODES":
			maximumModeCount = UInt(IRCProtocolLimits.maximumNodesPerModeCommand)
		case "NICKLEN":
			maximumNicknameLength = UInt(IRCProtocolLimits.defaultNicknameMaximumLength)
		case "SILENCE":
			silenceSupported = false
			maximumSilenceEntries = 0
		case "TOPICLEN":
			maximumTopicLength = 0
		default:
			return false
		}

		return true
	}

	private func resetModeSetting(_ key: String) -> Bool {
		switch key {
		case "BOT":
			botModeSymbol = nil
		case "CALLERID":
			callerIDModeSymbol = nil
		case "CASEMAPPING":
			caseMapping = .rfc1459
		case "CHANTYPES":
			channelNamePrefixes = ["#"]
		case "DEAF":
			deafModeSymbol = nil
		case "EXCEPTS":
			banExceptionModeSymbol = nil
		case "INVEX":
			inviteExceptionModeSymbol = nil
		case "PREFIX":
			userModePrefixPairs = defaultUserModePrefixPairs
		case "STATUSMSG":
			statusMessageModeSymbols = []
		default:
			return false
		}

		return true
	}

	private func resetCollectionSetting(_ key: String) -> Bool {
		switch key {
		case "CHANLIMIT":
			channelLimits = [:]
		case "CLIENTTAGDENY":
			clientTagDenyList = []
		case "ELIST":
			extendedListTokens = []
		case "EXTBAN":
			extendedBanPrefix = nil
			extendedBanTypes = []
		case "MAXLIST":
			maximumListEntries = [:]
		case "NETWORK":
			networkName = nil
			networkNameFormatted = nil
		case "TARGMAX":
			maximumTargetsByCommand = [:]
		default:
			return false
		}

		return true
	}

	private func resetFeatureSetting(_ key: String) {
		switch key {
		case "SAFELIST":
			safeListSupported = false
		case "UTF8ONLY":
			utf8Only = false
		case "WHOX":
			whoxSupported = false
		default:
			break
		}
	}

	public func removeCachedSetting(_ key: String) {
		var updatedConfiguration: [[String: ISupportValue]] = []

		for configuration in cachedConfiguration {
			var configurationMutable = configuration

			for cachedKey in configuration.keys where cachedKey.caseInsensitiveCompare(key) == .orderedSame {
				configurationMutable.removeValue(forKey: cachedKey)
			}

			if configurationMutable.isEmpty == false {
				updatedConfiguration.append(configurationMutable)
			}
		}

		cachedConfiguration = updatedConfiguration
	}

	/// The tokens whose value is a list of characters, and for which
	/// modern.ircdocs.horse therefore reads an explicitly empty value as "the
	/// server has none of these" rather than as the bare token.
	private static let keysWithMeaningfulEmptyValue: Set<String> = ["CHANTYPES", "PREFIX", "STATUSMSG"]

	public func processConfigurationData(_ configurationData: String) {
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
				segmentValue = String(segment[segment.index(after: equalSignIndex)...])

				/* For most tokens an empty value says no more than the bare
				 token does, but modern.ircdocs.horse gives one a meaning of its
				 own for the three that list characters: the server has none. */
				if segmentValue?.isEmpty == true,
				   Self.keysWithMeaningfulEmptyValue.contains(segmentKey.uppercased()) == false
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

			if let segmentValue {
				processValueSegment(segmentKey: segmentKey, segmentValue: segmentValue)
			}

			processFlagSegment(segmentKey: segmentKey, segmentValue: segmentValue, client: client)
		}

		if configuration.isEmpty == false {
			cachedConfiguration.append(configuration)
		}
	}

	public func channelLimit(forChannelNamed channel: String) -> UInt {
		if channel.isEmpty {
			return 0
		}

		guard let prefix = channel.first else {
			return 0
		}

		return channelLimits[prefix] ?? 0
	}

	public func maximumTargets(forCommand command: String) -> UInt {
		if let limit = maximumTargetsByCommand[command.uppercased()] {
			return limit
		}

		return maximumTargets
	}

	public static func chunkTargets(_ targets: [String], limit: UInt) -> [[String]] {
		ISupportTokenParser.chunkTargets(targets, limit: limit)
	}

	public func maximumListEntries(forModeSymbol modeSymbol: ChannelModeSymbol) -> UInt {
		maximumListEntries[modeSymbol.character] ?? 0
	}

	public func extendedListSupportsToken(_ token: String) -> Bool {
		extendedListTokens.contains(token.uppercased())
	}

	public func isClientTagDenied(_ tagName: String) -> Bool {
		ISupportTokenParser.isClientTag(tagName, deniedBy: clientTagDenyList)
	}

	public func descriptionForExtendedBanMask(_ mask: String) -> String? {
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
			return IRCISupportStrings.everyoneExcept(description)
		}

		return description
	}

	public static func localizedDescription(forExtendedBanType type: String, argument: String?) -> String {
		IRCISupportStrings.extendedBanDescription(type: type, argument: argument)
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

	public func parseModes(_ modeString: String) -> [ModeInfo] {
		ModeParser.parse(modeString, channelModeKinds: channelModeKinds)
	}

	public func casefoldString(_ string: String) -> String {
		ISupportTokenParser.casefold(string, caseMapping: caseMapping)
	}

	public func modeHasParameter(_ modeSymbol: String, whenModeIsSet: Bool) -> Bool {
		guard let symbol = modeSymbol.first, modeSymbol.count == 1 else {
			return false
		}

		let policy = channelModeKinds[symbol]?.parameterPolicy ?? .never

		return policy.requiresParameter(whenModeIsSet: whenModeIsSet)
	}

	public func userPrefix(forModeSymbol modeSymbol: String) -> String? {
		userModePrefixPairs.first { $0.modeSymbol == modeSymbol }?.character
	}

	public func modeSymbolIsUserPrefix(_ modeSymbol: String) -> Bool {
		userPrefix(forModeSymbol: modeSymbol) != nil
	}

	public func modeSymbol(forUserPrefix character: String) -> String? {
		userModePrefixPairs.first { $0.character == character }?.modeSymbol
	}

	public func characterIsUserPrefix(_ character: String) -> Bool {
		modeSymbol(forUserPrefix: character) != nil
	}

	public func rankForUserPrefix(withMode modeSymbol: String) -> UInt {
		guard let modeSymbolIndex = userModePrefixPairs.firstIndex(where: { $0.modeSymbol == modeSymbol })
		else {
			return 0
		}

		// A server may advertise more prefix modes than the rank ceiling; the
		// lowest-ranked ones all collapse to rank 1 rather than underflowing.
		guard UInt(modeSymbolIndex) < IRCISupportUserModes.highestPrefixRank else {
			return 1
		}

		return IRCISupportUserModes.highestPrefixRank - UInt(modeSymbolIndex)
	}

	public func extractStatusMessagePrefix(fromChannelNamed channel: String) -> String {
		extractCharacters(statusMessageModeSymbols, fromChannelNamed: channel)
	}

	public func createMode(withSymbol modeSymbol: String) -> ModeInfo {
		ModeInfo(modeSymbol: modeSymbol)
	}

	public func createMode(
		withSymbol modeSymbol: String,
		modeIsSet: Bool,
		modeParameter: String?
	) -> ModeInfo {
		ModeInfo(modeSymbol: modeSymbol, modeIsSet: modeIsSet, modeParameter: modeParameter)
	}

	public func isListSupported(_ listType: IRCISupportInfoListType) -> Bool {
		modeSymbol(forList: listType) != nil
	}

	public func modeSymbol(forList listType: IRCISupportInfoListType) -> String? {
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
		@unknown default:
			return nil
		}
	}

	public func statusMessagePrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let character = userPrefix(forModeSymbol: modeSymbol) else {
			return nil
		}

		if statusMessageModeSymbols.contains(character) == false {
			return nil
		}

		return character
	}
}

private extension IRCISupportInfo {
	func prepareInitialState() {
		reset()
	}

	func processValueSegment(segmentKey: String, segmentValue: String) {
		let normalizedKey = segmentKey.uppercased()

		if processPositiveLengthValue(normalizedKey, value: segmentValue) {
			return
		}

		if processChannelValue(normalizedKey, value: segmentValue) {
			return
		}

		processCollectionValue(normalizedKey, value: segmentValue)
	}

	func processPositiveLengthValue(_ key: String, value: String) -> Bool {
		guard let parsedValue = positiveInteger(from: value) else {
			return false
		}

		switch key {
		case "AWAYLEN":
			maximumAwayLength = parsedValue
		case "CHANNELLEN":
			maximumChannelNameLength = parsedValue
		case "CHATHISTORY", "DRAFT/CHATHISTORY":
			chatHistoryMaximumLines = parsedValue
		case "KEYLEN":
			maximumKeyLength = parsedValue
		case "KICKLEN":
			maximumKickLength = parsedValue
		case "LINELEN":
			maximumLineLength = parsedValue
		case "MAXTARGETS":
			maximumTargets = parsedValue
		case "MODES":
			maximumModeCount = parsedValue
		case "NICKLEN":
			maximumNicknameLength = parsedValue
		case "TOPICLEN":
			maximumTopicLength = parsedValue
		default:
			return false
		}

		return true
	}

	func processChannelValue(_ key: String, value: String) -> Bool {
		switch key {
		case "CASEMAPPING":
			parseCaseMapping(value)
		case "CHANMODES":
			channelModeKinds = ISupportTokenParser.channelModeKinds(from: value, merging: channelModeKinds)
		case "CHANTYPES":
			updateChannelNamePrefixes(from: value)
		case "NETWORK":
			networkName = value
			networkNameFormatted = IRCISupportStrings.networkName(value)
		case "PREFIX":
			parseUserModeSymbols(value)
		case "STATUSMSG":
			statusMessageModeSymbols = value.map(String.init)
		default:
			return false
		}

		return true
	}

	func processCollectionValue(_ key: String, value: String) {
		switch key {
		case "CHANLIMIT":
			channelLimits = ISupportTokenParser.channelLimits(from: value)
		case "CLIENTTAGDENY":
			clientTagDenyList = value.components(separatedBy: ",")
		case "ELIST":
			extendedListTokens = value.uppercased().map(String.init)
		case "EXTBAN":
			let configuration = ISupportTokenParser.extendedBanConfiguration(from: value)
			extendedBanPrefix = configuration.prefix
			extendedBanTypes = configuration.types
		case "MAXLIST":
			maximumListEntries = ISupportTokenParser.maximumListEntries(from: value)
		case "TARGMAX":
			maximumTargetsByCommand = ISupportTokenParser.maximumTargets(from: value)
		default:
			break
		}
	}

	func positiveInteger(from value: String) -> UInt? {
		let parsedValue = (value as NSString).integerValue
		return parsedValue > 0 ? UInt(parsedValue) : nil
	}

	/// An empty `CHANTYPES` is the server saying it supports no channel types
	/// at all, which is not the same as it saying nothing.
	func updateChannelNamePrefixes(from value: String) {
		channelNamePrefixes = value.map(String.init)
	}

	func processFlagSegment(segmentKey: String, segmentValue: String?, client: IRCClient?) {
		let normalizedKey = segmentKey.uppercased()

		if processModeFlag(normalizedKey, value: segmentValue) {
			return
		}

		if processCapabilityFlag(normalizedKey, client: client) {
			return
		}

		processAvailabilityFlag(normalizedKey, value: segmentValue)
	}

	func processModeFlag(_ key: String, value: String?) -> Bool {
		switch key {
		case "BOT":
			if value?.isModeSymbol == true {
				botModeSymbol = value
			}
		case "CALLERID":
			callerIDModeSymbol = validatedModeSymbol(value, fallback: "g")
		case "DEAF":
			deafModeSymbol = validatedModeSymbol(value, fallback: "D")
		case "EXCEPTS":
			banExceptionModeSymbol = validatedModeSymbol(value, fallback: "e")
		case "INVEX":
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

	func processCapabilityFlag(_ key: String, client: IRCClient?) -> Bool {
		switch key {
		case "MONITOR":
			client?.enableCapability(.monitorCommand)
		case "NAMESX":
			enableLegacyCapability(.multiPrefix, command: "PROTOCTL NAMESX", on: client)
		case "UHNAMES":
			enableLegacyCapability(.userhostInNames, command: "PROTOCTL UHNAMES", on: client)
		case "WATCH":
			client?.enableCapability(.watchCommand)
		default:
			return false
		}

		return true
	}

	func enableLegacyCapability(
		_ capability: ClientIRCv3SupportedCapability,
		command: String,
		on client: IRCClient?
	) {
		guard let client, client.isCapabilityEnabled(capability) == false else {
			return
		}

		client.sendLine(command)
		client.enableCapability(capability)
	}

	func processAvailabilityFlag(_ key: String, value: String?) {
		switch key {
		case "SAFELIST":
			safeListSupported = true
		case "SILENCE":
			silenceSupported = true
			if let value, let limit = positiveInteger(from: value) {
				maximumSilenceEntries = limit
			}
		case "UTF8ONLY":
			utf8Only = true
		case "WHOX":
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
		} else if caseMapping.caseInsensitiveCompare("rfc7613") == .orderedSame {
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

		var updatedChannelModes = channelModeKinds

		for modeSymbol in configuration.modeSymbols.compactMap(\.first) {
			updatedChannelModes[modeSymbol] = .userPrefix
		}

		channelModeKinds = updatedChannelModes
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
