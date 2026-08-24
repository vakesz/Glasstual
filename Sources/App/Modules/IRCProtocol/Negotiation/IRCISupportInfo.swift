/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

private let channelUserModeValue = 100

@objc(IRCISupportInfo)
public class IRCISupportInfo: NSObject {
	@objc public private(set) weak var client: IRCClient?
	@objc public private(set) var serverAddress: String?
	@objc public private(set) var maximumAwayLength: UInt = 0
	@objc public private(set) var maximumChannelNameLength: UInt = 0
	@objc public private(set) var maximumKeyLength: UInt = 0
	@objc public private(set) var maximumKickLength: UInt = 0
	@objc public private(set) var maximumNicknameLength: UInt = 0
	@objc public private(set) var maximumTopicLength: UInt = 0
	@objc public private(set) var maximumModeCount: UInt = 0
	@objc public private(set) var maximumLineLength: UInt = 0
	@objc public private(set) var maximumTargets: UInt = 0
	@objc public private(set) var maximumSilenceEntries: UInt = 0
	@objc public private(set) var chatHistoryMaximumLines: UInt = 0
	@objc public private(set) var silenceSupported = false
	@objc public private(set) var safeListSupported = false
	@objc public private(set) var whoxSupported = false
	@objc public private(set) var utf8Only = false
	@objc public private(set) var channelNamePrefixes: [String] = ["#"]
	@objc public private(set) var statusMessageModeSymbols: [String] = []
	@objc public private(set) var extendedBanTypes: [String] = []
	@objc public private(set) var extendedListTokens: [String] = []
	@objc public private(set) var clientTagDenyList: [String] = []
	@objc public private(set) var channelModes: [String: NSNumber] = [
		"o": NSNumber(value: channelUserModeValue), "v": NSNumber(value: channelUserModeValue),
	]
	@objc public private(set) var channelLimits: [String: NSNumber] = [:]
	@objc public private(set) var maximumListEntries: [String: NSNumber] = [:]
	@objc public private(set) var maximumTargetsByCommand: [String: NSNumber] = [:]
	@objc public private(set) var userModeSymbols: [String: [String]] = [
		IRCISupportUserModeSymbolsSymbolsKey: ["o", "v"],
		IRCISupportUserModeSymbolsCharactersKey: ["@", "+"],
	]
	@objc public private(set) var banExceptionModeSymbol: String?
	@objc public private(set) var inviteExceptionModeSymbol: String?
	@objc public private(set) var botModeSymbol: String?
	@objc public private(set) var callerIDModeSymbol: String?
	@objc public private(set) var deafModeSymbol: String?
	@objc public private(set) var extendedBanPrefix: String?
	@objc public private(set) var networkName: String?
	@objc public private(set) var networkNameFormatted: String?
	@objc public private(set) var caseMapping: IRCISupportInfoCaseMapping = .RFC1459

	private var cachedConfiguration: [[String: Any]] = []

	override public init() {
		client = nil
		super.init()
		prepareInitialState()
	}

	@objc(initWithClient:)
	public init(client: IRCClient?) {
		self.client = client
		super.init()
		prepareInitialState()
	}

	@objc public var configurationReceived: Bool {
		cachedConfiguration.isEmpty == false
	}

	@objc public var stringValueForLastUpdate: String? {
		guard let configuration = cachedConfiguration.last else {
			return nil
		}

		return stringValue(forConfiguration: configuration)
	}

	@objc public func reset() {
		cachedConfiguration = []
		serverAddress = nil
		userModeSymbols = [
			IRCISupportUserModeSymbolsSymbolsKey: ["o", "v"],
			IRCISupportUserModeSymbolsCharactersKey: ["@", "+"],
		]
		channelModes = ["o": NSNumber(value: channelUserModeValue), "v": NSNumber(value: channelUserModeValue)]

		for key in Self.resettableSettings() {
			resetSetting(key)
		}
	}

	@objc(resettableSettings)
	public static func resettableSettings() -> [String] {
		[
			"AWAYLEN", "BOT", "CALLERID", "CASEMAPPING", "CHANLIMIT", "CHANNELLEN",
			"CHANTYPES", "CHATHISTORY", "CLIENTTAGDENY", "DEAF", "ELIST", "EXCEPTS",
			"EXTBAN", "INVEX", "KEYLEN", "KICKLEN", "LINELEN", "MAXLIST",
			"MAXTARGETS", "MODES", "NETWORK", "NICKLEN", "SAFELIST", "SILENCE",
			"STATUSMSG", "TARGMAX", "TOPICLEN", "UTF8ONLY", "WHOX",
		]
	}

	@objc(resetSetting:)
	public func resetSetting(_ key: String) {
		let normalizedKey = key.uppercased()

		switch normalizedKey {
		case "AWAYLEN":
			maximumAwayLength = 0
		case "BOT":
			botModeSymbol = nil
		case "CALLERID":
			callerIDModeSymbol = nil
		case "CASEMAPPING":
			caseMapping = .RFC1459
		case "CHANLIMIT":
			channelLimits = [:]
		case "CHANNELLEN":
			maximumChannelNameLength = 0
		case "CHANTYPES":
			channelNamePrefixes = ["#"]
		case "CHATHISTORY", "DRAFT/CHATHISTORY":
			chatHistoryMaximumLines = 0
		case "CLIENTTAGDENY":
			clientTagDenyList = []
		case "DEAF":
			deafModeSymbol = nil
		case "ELIST":
			extendedListTokens = []
		case "EXCEPTS":
			banExceptionModeSymbol = nil
		case "EXTBAN":
			extendedBanPrefix = nil
			extendedBanTypes = []
		case "INVEX":
			inviteExceptionModeSymbol = nil
		case "KEYLEN":
			maximumKeyLength = 0
		case "KICKLEN":
			maximumKickLength = 0
		case "LINELEN":
			maximumLineLength = 0
		case "MAXLIST":
			maximumListEntries = [:]
		case "MAXTARGETS":
			maximumTargets = 0
		case "MODES":
			maximumModeCount = 4
		case "NETWORK":
			networkName = nil
			networkNameFormatted = nil
		case "NICKLEN":
			maximumNicknameLength = 31
		case "SAFELIST":
			safeListSupported = false
		case "SILENCE":
			silenceSupported = false
			maximumSilenceEntries = 0
		case "STATUSMSG":
			statusMessageModeSymbols = []
		case "TARGMAX":
			maximumTargetsByCommand = [:]
		case "TOPICLEN":
			maximumTopicLength = 0
		case "UTF8ONLY":
			utf8Only = false
		case "WHOX":
			whoxSupported = false
		default:
			break
		}
	}

	@objc(removeCachedSetting:)
	public func removeCachedSetting(_ key: String) {
		var updatedConfiguration: [[String: Any]] = []

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

	@objc(processConfigurationData:)
	public func processConfigurationData(_ configurationData: String) {
		var trimmed = configurationData.trimmingCharacters(in: .whitespacesAndNewlines)

		if trimmed.isEmpty {
			return
		}

		let client = client
		var configuration: [String: Any] = [:]
		let segments = trimmed.components(separatedBy: .whitespaces)

		for segment in segments where segment.isEmpty == false {
			var segmentKey = segment
			var segmentValue: String?

			let equalSignPosition = (segment as NSString).stringPosition("=")

			if equalSignPosition > 0 {
				segmentKey = (segment as NSString).substring(to: equalSignPosition)
				segmentValue = (segment as NSString).substring(after: UInt(equalSignPosition))

				if segmentValue?.isEmpty == true {
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

			if let segmentValue {
				configuration[segmentKey] = segmentValue
			} else {
				configuration[segmentKey] = true
			}

			if let segmentValue {
				processValueSegment(segmentKey: segmentKey, segmentValue: segmentValue)
			}

			processFlagSegment(segmentKey: segmentKey, segmentValue: segmentValue, client: client)
		}

		if configuration.isEmpty == false {
			cachedConfiguration.append(configuration)
		}
	}

	@objc(channelLimitForChannelNamed:)
	public func channelLimit(forChannelNamed channel: String) -> UInt {
		if channel.isEmpty {
			return 0
		}

		let prefix = (channel as NSString).stringCharacter(at: 0)

		return channelLimits[prefix]?.uintValue ?? 0
	}

	@objc(maximumTargetsForCommand:)
	public func maximumTargets(forCommand command: String) -> UInt {
		if let limit = maximumTargetsByCommand[command.uppercased()] {
			return limit.uintValue
		}

		return maximumTargets
	}

	@objc(chunkTargets:limit:)
	public static func chunkTargets(_ targets: [String], limit: UInt) -> [[String]] {
		ISupportTokenParser.chunkTargets(targets, limit: limit)
	}

	@objc(maximumListEntriesForModeSymbol:)
	public func maximumListEntries(forModeSymbol modeSymbol: String) -> UInt {
		maximumListEntries[modeSymbol]?.uintValue ?? 0
	}

	@objc(extendedListSupportsToken:)
	public func extendedListSupportsToken(_ token: String) -> Bool {
		extendedListTokens.contains(token.uppercased())
	}

	@objc(isClientTagDenied:)
	public func isClientTagDenied(_ tagName: String) -> Bool {
		ISupportTokenParser.isClientTag(tagName, deniedBy: clientTagDenyList)
	}

	@objc(descriptionForExtendedBanMask:)
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

		let type = (body as NSString).stringCharacter(at: 0)

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
			return LocalizedKey("IRC[6kq-xb]", description)
		}

		return description
	}

	@objc(localizedDescriptionForExtendedBanType:argument:)
	public static func localizedDescription(forExtendedBanType type: String, argument: String?) -> String {
		let table: [String: String] = [
			"a": "IRC[2nb-ka]",
			"c": "IRC[2nb-kc]",
			"j": "IRC[2nb-kj]",
			"m": "IRC[2nb-km]",
			"n": "IRC[2nb-kn]",
			"o": "IRC[2nb-ko]",
			"O": "IRC[2nb-ko2]",
			"q": "IRC[2nb-kq]",
			"r": "IRC[2nb-kr]",
			"R": "IRC[2nb-kr2]",
			"s": "IRC[2nb-ks]",
			"S": "IRC[2nb-ks2]",
			"t": "IRC[2nb-kt]",
			"T": "IRC[2nb-kt2]",
			"U": "IRC[2nb-ku]",
			"x": "IRC[2nb-kx]",
			"z": "IRC[2nb-kz]",
		]

		if let key = table[type] {
			if argument == nil {
				return LocalizedKey("IRC[2nb-kl]", type)
			}

			return LocalizedKey(key, argument!)
		}

		if let argument {
			return LocalizedKey("IRC[2nb-kk]", type, argument)
		}

		return LocalizedKey("IRC[2nb-kl]", type)
	}

	@objc(stringValueForConfiguration:)
	public func stringValue(forConfiguration configuration: [String: Any]) -> String? {
		if configuration.isEmpty {
			return nil
		}

		var stringValue = ""
		let sortedKeys =
			(configuration as NSDictionary).sortedDictionaryKeys as? [String] ?? configuration.keys.sorted()

		for key in sortedKeys {
			let value = configuration[key]

			if let value = value as? String {
				stringValue.append("\u{02}\(key)\u{02}=\(value) ")
			} else {
				stringValue.append("\u{02}\(key) \u{02}")
			}
		}

		return stringValue
	}

	@objc(parseModes:)
	public func parseModes(_ modeString: String) -> [ModeInfo] {
		ModeParser.parse(modeString, channelModes: channelModes)
	}

	@objc(casefoldString:)
	public func casefoldString(_ string: String) -> String {
		ISupportTokenParser.casefold(string, caseMapping: caseMapping.rawValue)
	}

	@objc(modeHasParameter:whenModeIsSet:)
	public func modeHasParameter(_ modeSymbol: String, whenModeIsSet: Bool) -> Bool {
		let modeIndex = (channelModes as NSDictionary).unsignedInteger(forKey: modeSymbol)

		if modeIndex == 1 || modeIndex == 2 || modeIndex == channelUserModeValue {
			return true
		}

		if modeIndex == 3 {
			return whenModeIsSet
		}

		return false
	}

	@objc(userPrefixForModeSymbol:)
	public func userPrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let modeSymbols = userModeSymbols[IRCISupportUserModeSymbolsSymbolsKey],
		      let characters = userModeSymbols[IRCISupportUserModeSymbolsCharactersKey]
		else {
			return nil
		}

		let modeSymbolIndex = modeSymbols.firstIndex(of: modeSymbol)

		guard let modeSymbolIndex else {
			return nil
		}

		return characters[modeSymbolIndex]
	}

	@objc(modeSymbolIsUserPrefix:)
	public func modeSymbolIsUserPrefix(_ modeSymbol: String) -> Bool {
		userPrefix(forModeSymbol: modeSymbol) != nil
	}

	@objc(modeSymbolForUserPrefix:)
	public func modeSymbol(forUserPrefix character: String) -> String? {
		guard let characters = userModeSymbols[IRCISupportUserModeSymbolsCharactersKey],
		      let modeSymbols = userModeSymbols[IRCISupportUserModeSymbolsSymbolsKey]
		else {
			return nil
		}

		let characterIndex = characters.firstIndex(of: character)

		guard let characterIndex else {
			return nil
		}

		return modeSymbols[characterIndex]
	}

	@objc(characterIsUserPrefix:)
	public func characterIsUserPrefix(_ character: String) -> Bool {
		modeSymbol(forUserPrefix: character) != nil
	}

	@objc(rankForUserPrefixWithMode:)
	public func rankForUserPrefix(withMode modeSymbol: String) -> UInt {
		guard let modeSymbols = userModeSymbols[IRCISupportUserModeSymbolsSymbolsKey] else {
			return 0
		}

		let modeSymbolIndex = modeSymbols.firstIndex(of: modeSymbol)

		guard let modeSymbolIndex else {
			return 0
		}

		return UInt(IRCISupportInfoHighestUserPrefixRank) - UInt(modeSymbolIndex)
	}

	@objc(extractStatusMessagePrefixFromChannelNamed:)
	public func extractStatusMessagePrefix(fromChannelNamed channel: String) -> String {
		extractCharacters(statusMessageModeSymbols, fromChannelNamed: channel)
	}

	@objc(createModeWithSymbol:)
	public func createMode(withSymbol modeSymbol: String) -> ModeInfo {
		ModeInfo(modeSymbol: modeSymbol)
	}

	@objc(createModeWithSymbol:modeIsSet:modeParameter:)
	public func createMode(
		withSymbol modeSymbol: String,
		modeIsSet: Bool,
		modeParameter: String?
	) -> ModeInfo {
		ModeInfo(modeSymbol: modeSymbol, modeIsSet: modeIsSet, modeParameter: modeParameter)
	}

	@objc(isListSupported:)
	public func isListSupported(_ listType: IRCISupportInfoListType) -> Bool {
		modeSymbol(forList: listType) != nil
	}

	@objc(modeSymbolForList:)
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

	@objc(statusMessagePrefixForModeSymbol:)
	public func statusMessagePrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let character = userPrefix(forModeSymbol: modeSymbol) else {
			return nil
		}

		if statusMessageModeSymbols.contains(character) == false {
			return nil
		}

		return character
	}

	private func prepareInitialState() {
		reset()
	}

	private func processValueSegment(segmentKey: String, segmentValue: String) {
		if segmentKey.caseInsensitiveCompare("AWAYLEN") == .orderedSame {
			let awayLength = (segmentValue as NSString).integerValue

			if awayLength > 0 {
				maximumAwayLength = UInt(awayLength)
			}
		} else if segmentKey.caseInsensitiveCompare("CASEMAPPING") == .orderedSame {
			parseCaseMapping(segmentValue)
		} else if segmentKey.caseInsensitiveCompare("CHANLIMIT") == .orderedSame {
			channelLimits = ISupportTokenParser.channelLimits(from: segmentValue)
		} else if segmentKey.caseInsensitiveCompare("CHANMODES") == .orderedSame {
			channelModes = ISupportTokenParser.channelModes(from: segmentValue, merging: channelModes)
		} else if segmentKey.caseInsensitiveCompare("CHANNELLEN") == .orderedSame {
			let channelNameLength = (segmentValue as NSString).integerValue

			if channelNameLength > 0 {
				maximumChannelNameLength = UInt(channelNameLength)
			}
		} else if segmentKey.caseInsensitiveCompare("CHANTYPES") == .orderedSame {
			let prefixes = segmentValue.characterStringBuffer

			if prefixes.isEmpty == false {
				channelNamePrefixes = prefixes
			}
		} else if segmentKey.caseInsensitiveCompare("CHATHISTORY") == .orderedSame
			|| segmentKey.caseInsensitiveCompare("draft/CHATHISTORY") == .orderedSame
		{
			let chatHistoryMaximumLines = (segmentValue as NSString).integerValue

			if chatHistoryMaximumLines > 0 {
				self.chatHistoryMaximumLines = UInt(chatHistoryMaximumLines)
			}
		} else if segmentKey.caseInsensitiveCompare("CLIENTTAGDENY") == .orderedSame {
			clientTagDenyList = (segmentValue as NSString).split(",") as? [String] ?? []
		} else if segmentKey.caseInsensitiveCompare("ELIST") == .orderedSame {
			extendedListTokens = segmentValue.uppercased().characterStringBuffer
		} else if segmentKey.caseInsensitiveCompare("EXTBAN") == .orderedSame {
			let configuration = ISupportTokenParser.extendedBanConfiguration(from: segmentValue)
			extendedBanPrefix = configuration.prefix
			extendedBanTypes = configuration.types
		} else if segmentKey.caseInsensitiveCompare("KEYLEN") == .orderedSame {
			let maximumKeyLength = (segmentValue as NSString).integerValue

			if maximumKeyLength > 0 {
				self.maximumKeyLength = UInt(maximumKeyLength)
			}
		} else if segmentKey.caseInsensitiveCompare("KICKLEN") == .orderedSame {
			let maximumKickLength = (segmentValue as NSString).integerValue

			if maximumKickLength > 0 {
				self.maximumKickLength = UInt(maximumKickLength)
			}
		} else if segmentKey.caseInsensitiveCompare("LINELEN") == .orderedSame {
			let maximumLineLength = (segmentValue as NSString).integerValue

			if maximumLineLength > 0 {
				self.maximumLineLength = UInt(maximumLineLength)
			}
		} else if segmentKey.caseInsensitiveCompare("MAXLIST") == .orderedSame {
			maximumListEntries = ISupportTokenParser.maximumListEntries(from: segmentValue)
		} else if segmentKey.caseInsensitiveCompare("MAXTARGETS") == .orderedSame {
			let maximumTargets = (segmentValue as NSString).integerValue

			if maximumTargets > 0 {
				self.maximumTargets = UInt(maximumTargets)
			}
		} else if segmentKey.caseInsensitiveCompare("MODES") == .orderedSame {
			let maximumModesCount = (segmentValue as NSString).integerValue

			if maximumModesCount > 0 {
				maximumModeCount = UInt(maximumModesCount)
			}
		} else if segmentKey.caseInsensitiveCompare("NETWORK") == .orderedSame {
			networkName = segmentValue
			networkNameFormatted = LocalizedKey("IRC[8hg-7k]", segmentValue)
		} else if segmentKey.caseInsensitiveCompare("NICKLEN") == .orderedSame {
			let maximumNicknameLength = (segmentValue as NSString).integerValue

			if maximumNicknameLength > 0 {
				self.maximumNicknameLength = UInt(maximumNicknameLength)
			}
		} else if segmentKey.caseInsensitiveCompare("PREFIX") == .orderedSame {
			parseUserModeSymbols(segmentValue)
		} else if segmentKey.caseInsensitiveCompare("STATUSMSG") == .orderedSame {
			statusMessageModeSymbols = segmentValue.characterStringBuffer
		} else if segmentKey.caseInsensitiveCompare("TARGMAX") == .orderedSame {
			maximumTargetsByCommand = ISupportTokenParser.maximumTargets(from: segmentValue)
		} else if segmentKey.caseInsensitiveCompare("TOPICLEN") == .orderedSame {
			let maximumTopicLength = (segmentValue as NSString).integerValue

			if maximumTopicLength > 0 {
				self.maximumTopicLength = UInt(maximumTopicLength)
			}
		}
	}

	private func processFlagSegment(segmentKey: String, segmentValue: String?, client: IRCClient?) {
		if segmentKey.caseInsensitiveCompare("BOT") == .orderedSame {
			if segmentValue?.isModeSymbol == true {
				botModeSymbol = segmentValue
			}
		} else if segmentKey.caseInsensitiveCompare("CALLERID") == .orderedSame {
			if segmentValue?.isModeSymbol == true {
				callerIDModeSymbol = segmentValue
			} else {
				callerIDModeSymbol = "g"
			}
		} else if segmentKey.caseInsensitiveCompare("DEAF") == .orderedSame {
			if segmentValue?.isModeSymbol == true {
				deafModeSymbol = segmentValue
			} else {
				deafModeSymbol = "D"
			}
		} else if segmentKey.caseInsensitiveCompare("EXCEPTS") == .orderedSame {
			if segmentValue?.isModeSymbol == true {
				banExceptionModeSymbol = segmentValue
			} else {
				banExceptionModeSymbol = "e"
			}
		} else if segmentKey.caseInsensitiveCompare("INVEX") == .orderedSame {
			if segmentValue?.isModeSymbol == true {
				inviteExceptionModeSymbol = segmentValue
			} else {
				inviteExceptionModeSymbol = "I"
			}
		} else if segmentKey.caseInsensitiveCompare("MONITOR") == .orderedSame {
			client?.enableCapability(.monitorCommand)
		} else if segmentKey.caseInsensitiveCompare("NAMESX") == .orderedSame {
			if let client, client.isCapabilityEnabled(.multiPrefix) == false {
				client.sendLine("PROTOCTL NAMESX")
				client.enableCapability(.multiPrefix)
			}
		} else if segmentKey.caseInsensitiveCompare("SAFELIST") == .orderedSame {
			safeListSupported = true
		} else if segmentKey.caseInsensitiveCompare("SILENCE") == .orderedSame {
			silenceSupported = true

			if let segmentValue {
				let maximumSilenceEntries = (segmentValue as NSString).integerValue

				if maximumSilenceEntries > 0 {
					self.maximumSilenceEntries = UInt(maximumSilenceEntries)
				}
			}
		} else if segmentKey.caseInsensitiveCompare("UHNAMES") == .orderedSame {
			if let client, client.isCapabilityEnabled(.userhostInNames) == false {
				client.sendLine("PROTOCTL UHNAMES")
				client.enableCapability(.userhostInNames)
			}
		} else if segmentKey.caseInsensitiveCompare("UTF8ONLY") == .orderedSame {
			utf8Only = true
		} else if segmentKey.caseInsensitiveCompare("WATCH") == .orderedSame {
			client?.enableCapability(.watchCommand)
		} else if segmentKey.caseInsensitiveCompare("WHOX") == .orderedSame {
			whoxSupported = true
		}
	}

	private func parseCaseMapping(_ caseMapping: String) {
		if caseMapping.caseInsensitiveCompare("ascii") == .orderedSame {
			self.caseMapping = .ASCII
		} else if caseMapping.caseInsensitiveCompare("strict-rfc1459") == .orderedSame {
			self.caseMapping = .strictRFC1459
		} else {
			self.caseMapping = .RFC1459
		}
	}

	private func parseUserModeSymbols(_ modeString: String) {
		guard let configuration = ISupportTokenParser.userPrefixConfiguration(from: modeString) else {
			return
		}

		userModeSymbols = [
			IRCISupportUserModeSymbolsSymbolsKey: configuration.modeSymbols,
			IRCISupportUserModeSymbolsCharactersKey: configuration.characters,
		]

		var updatedChannelModes = channelModes

		for modeSymbol in configuration.modeSymbols {
			updatedChannelModes[modeSymbol] = NSNumber(value: channelUserModeValue)
		}

		channelModes = updatedChannelModes
	}

	private func extractCharacters(_ characters: [String], fromChannelNamed channel: String) -> String {
		if channel.count < 2 {
			return ""
		}

		for character in characters where channel.hasPrefix(character) {
			let nextCharacter = (channel as NSString).stringCharacter(at: 1)

			if channelNamePrefixes.contains(nextCharacter) {
				return character
			}
		}

		return ""
	}
}
