/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

private func isBase10Numeric(_ character: unichar) -> Bool {
	character >= 0x30 && character <= 0x39
}

extension NSString {
	@objc(isValidInternetAddress)
	public var isValidInternetAddress: Bool {
		guard length > 0 else {
			return false
		}

		if isIPAddress || isEqual(to: "localhost") {
			return true
		}

		return onlyContainsCharacters(from: NSCharacterSet.ato9UnderscoreDashPeriod as CharacterSet)
	}

	@objc(isValidInternetPort)
	public var isValidInternetPort: Bool {
		guard isNumericOnly else {
			return false
		}

		let value = integerValue
		return value > 0 && value <= 65535
	}

	@objc public var stringByAppendingIRCFormattingStop: String {
		(self as String) + String(utf16CodeUnits: [UniChar(IRCTextFormatterTerminatingCharacter)], count: 1)
	}

	@objc(hostmaskComponents:username:address:)
	public func hostmaskComponents(
		_ nickname: AutoreleasingUnsafeMutablePointer<NSString?>?,
		username: AutoreleasingUnsafeMutablePointer<NSString?>?,
		address: AutoreleasingUnsafeMutablePointer<NSString?>?
	) -> Bool {
		hostmaskComponents(nickname, username: username, address: address, on: nil)
	}

	@objc(hostmaskComponents:username:address:onClient:)
	public func hostmaskComponents(
		_ nickname: AutoreleasingUnsafeMutablePointer<NSString?>?,
		username: AutoreleasingUnsafeMutablePointer<NSString?>?,
		address: AutoreleasingUnsafeMutablePointer<NSString?>?,
		on client: IRCClient?
	) -> Bool {
		guard length > 0 else {
			return false
		}

		let bang1pos = range(of: "!", options: .literal)
		let bang2pos = range(of: "@", options: [.literal, .backwards])

		guard bang1pos.location != NSNotFound,
			bang2pos.location != NSNotFound,
			bang2pos.location > bang1pos.location
		else {
			return false
		}

		let nicknameInt = substring(to: bang1pos.location) as NSString
		let usernameInt = substring(
			with: NSRange(
				location: bang1pos.location + 1,
				length: bang2pos.location - (bang1pos.location + 1)
			)
		) as NSString
		let addressInt = substring(after: UInt(bang2pos.location)) as NSString

		guard nicknameInt.isHostmaskNickname(on: client),
			usernameInt.isHostmaskUsername(on: client),
			addressInt.isHostmaskAddress(on: client)
		else {
			return false
		}

		nickname?.pointee = nicknameInt
		username?.pointee = usernameInt
		address?.pointee = addressInt

		return true
	}

	@objc(isHostmask)
	public var isHostmask: Bool {
		hostmaskComponents(nil, username: nil, address: nil)
	}

	@objc(isHostmaskAddress)
	public var isHostmaskAddress: Bool {
		isHostmaskAddress(on: nil)
	}

	@objc(isHostmaskAddressOn:)
	public func isHostmaskAddress(on _: IRCClient?) -> Bool {
		length > 0 && containsCharacters("\u{021}\u{040}\u{000}\u{020}\u{00d}\u{00a}") == false
	}

	@objc(isHostmaskUsername)
	public var isHostmaskUsername: Bool {
		isHostmaskUsername(on: nil)
	}

	@objc(isHostmaskUsernameOn:)
	public func isHostmaskUsername(on _: IRCClient?) -> Bool {
		length > 0
			&& length <= 40
			&& containsCharacters("\u{000}\u{020}\u{00d}\u{00a}") == false
	}

	@objc(isHostmaskNickname)
	public var isHostmaskNickname: Bool {
		isHostmaskNickname(on: nil)
	}

	@objc(isHostmaskNicknameOn:)
	public func isHostmaskNickname(on client: IRCClient?) -> Bool {
		var maximumLength: UInt = 50

		if let client {
			if client.supportInfo.configurationReceived {
				maximumLength = client.supportInfo.maximumNicknameLength
			} else {
				maximumLength = 0
			}

			if client.isConnectedToZNC {
				maximumLength = 0
			}
		}

		if maximumLength == 0 {
			maximumLength = 50
		}

		return (isEqual(to: "*") == false)
			&& length > 0
			&& length <= Int(maximumLength)
			&& containsCharacters("\u{021}\u{040}\u{000}\u{020}\u{00d}\u{00a}") == false
	}

	@objc(isChannelNameOn:)
	public func isChannelName(on client: IRCClient) -> Bool {
		guard length > 0 else {
			return false
		}

		let channelNamePrefixes = client.supportInfo.channelNamePrefixes as? [String] ?? []

		if length == 1 {
			let character = stringCharacter(at: 0) ?? ""
			return channelNamePrefixes.contains(character)
		}

		let character1 = stringCharacter(at: 0) ?? ""
		let character2 = stringCharacter(at: 1) ?? ""
		let isPartyline = (character1 == "~" && character2 == "#")

		return isPartyline || channelNamePrefixes.contains(character1)
	}

	@objc(isChannelName)
	public var isChannelName: Bool {
		guard length > 0 else {
			return false
		}

		let c = character(at: 0)
		return c == 0x23 || c == 0x26 || c == 0x2B || c == 0x21 || c == 0x7E || c == 0x3F
	}

	@objc public var channelNameWithoutBang: String? {
		guard isChannelName else {
			return self as String
		}

		return substring(from: 1)
	}

	@objc(channelNameWithoutBangOn:)
	public func channelNameWithoutBang(on client: IRCClient) -> String? {
		guard isChannelName(on: client) else {
			return self as String
		}

		guard length >= 2 else {
			return self as String
		}

		let channelNamePrefixes = client.supportInfo.channelNamePrefixes as? [String] ?? []
		let character = stringCharacter(at: 0) ?? ""

		if channelNamePrefixes.contains(character) {
			return substring(from: 1)
		}

		return self as String
	}

	@objc public var nicknameFromHostmask: String? {
		var nickname: NSString?
		if hostmaskComponents(&nickname, username: nil, address: nil) {
			return nickname as String?
		}

		return self as String
	}

	@objc public var usernameFromHostmask: String? {
		var username: NSString?
		if hostmaskComponents(nil, username: &username, address: nil) {
			return username as String?
		}

		return nil
	}

	@objc public var addressFromHostmask: String? {
		var address: NSString?
		if hostmaskComponents(nil, username: nil, address: &address) {
			return address as String?
		}

		return nil
	}

	@objc public var stringWithValidURIScheme: String? {
		LinkParser.urlWithProperScheme(self as String)
	}

	@objc(attributedStringWithIRCFormatting:preferredFontColor:honorFormattingPreference:)
	public func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?,
		honorFormattingPreference formattingPreference: Bool
	) -> NSAttributedString? {
		if formattingPreference, TPCPreferences.removeAllFormatting() {
			return NSAttributedString(string: stripIRCEffects)
		}

		var attributes: [TVCLogRendererConfigurationAttribute: Any] = [:]

		attributes[.attributedStringPreferredFontAttribute] = preferredFont

		if let preferredFontColor {
			attributes[.attributedStringPreferredFontColorAttribute] = preferredFontColor
		}

		return TVCLogRenderer.renderBody(asAttributedString: self as String, withAttributes: attributes)
	}

	@objc(attributedStringWithIRCFormatting:preferredFontColor:)
	public func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?
	) -> NSAttributedString? {
		attributedString(
			withIRCFormatting: preferredFont,
			preferredFontColor: preferredFontColor,
			honorFormattingPreference: false
		)
	}

	@objc public var stripIRCEffects: String {
		let stringLength = length

		guard stringLength > 0 else {
			return self as String
		}

		var inputBuffer = [UniChar](repeating: 0, count: stringLength)
		var outputBuffer = [UniChar](repeating: 0, count: stringLength)

		getCharacters(&inputBuffer, range: range)

		var currentPosition = 0
		var i = 0

		while i < stringLength {
			let character = inputBuffer[i]

			switch character {
			case UniChar(IRCTextFormatterEffectBoldCharacter),
				UniChar(IRCTextFormatterEffectItalicCharacter),
				UniChar(IRCTextFormatterEffectItalicCharacterOld),
				UniChar(IRCTextFormatterEffectMonospaceCharacter),
				UniChar(IRCTextFormatterEffectStrikethroughCharacter),
				UniChar(IRCTextFormatterEffectUnderlineCharacter),
				UniChar(IRCTextFormatterTerminatingCharacter):
				break
			case UniChar(IRCTextFormatterEffectColorAsDigitCharacter),
				UniChar(IRCTextFormatterEffectColorAsHexCharacter):
				i += Int(
					colorComponents(
						ofCharacter: character,
						startingAt: UInt(i),
						foregroundColor: nil,
						backgroundColor: nil
					)
				) - 1
			default:
				outputBuffer[currentPosition] = character
				currentPosition += 1
			}

			i += 1
		}

		return NSString(characters: outputBuffer, length: currentPosition) as String
	}

	@objc(colorComponentsOfCharacter:startingAt:foregroundColor:backgroundColor:)
	public func colorComponents(
		ofCharacter character: unichar,
		startingAt rangeStart: UInt,
		foregroundColor: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
		backgroundColor: AutoreleasingUnsafeMutablePointer<AnyObject?>?
	) -> UInt {
		if character == UniChar(IRCTextFormatterEffectColorAsDigitCharacter) {
			var foregroundNumber: NSNumber?
			var backgroundNumber: NSNumber?

			let consumed = colorAsDigit(
				startingAt: rangeStart,
				foregroundColor: &foregroundNumber,
				backgroundColor: &backgroundNumber
			)

			if let foregroundNumber {
				foregroundColor?.pointee = foregroundNumber
			}
			if let backgroundNumber {
				backgroundColor?.pointee = backgroundNumber
			}

			return consumed
		}

		if character == UniChar(IRCTextFormatterEffectColorAsHexCharacter) {
			var foregroundNSColor: NSColor?
			var backgroundNSColor: NSColor?

			let consumed = colorAsHex(
				startingAt: rangeStart,
				foregroundColor: &foregroundNSColor,
				backgroundColor: &backgroundNSColor
			)

			if let foregroundNSColor {
				foregroundColor?.pointee = foregroundNSColor
			}
			if let backgroundNSColor {
				backgroundColor?.pointee = backgroundNSColor
			}

			return consumed
		}

		return 0
	}

	private func colorAsHex(
		startingAt rangeStart: UInt,
		foregroundColor: inout NSColor?,
		backgroundColor: inout NSColor?
	) -> UInt {
		let selfLength = length
		precondition(Int(rangeStart) < selfLength)

		var currentPosition = Int(rangeStart)
		var mForegroundColor: String?
		var mBackgroundColor: String?
		var commaEaten = false

		currentPosition += 1

		func finish() -> UInt {
			if mBackgroundColor == nil, commaEaten {
				currentPosition -= 1
			}

			if let mForegroundColor {
				foregroundColor = NSColor(hexadecimalValue: mForegroundColor.uppercased())
			}

			if let mBackgroundColor {
				backgroundColor = NSColor(hexadecimalValue: mBackgroundColor.uppercased())
			}

			return UInt(currentPosition - Int(rangeStart))
		}

		guard currentPosition + 6 <= selfLength else {
			return finish()
		}

		let foregroundCandidate = substring(with: NSRange(location: currentPosition, length: 6)) as NSString

		if foregroundCandidate.onlyContainsCharacters(from: NSCharacterSet.hexadecimal as CharacterSet) {
			mForegroundColor = foregroundCandidate as String
			currentPosition += 6
		} else {
			return finish()
		}

		guard currentPosition < selfLength else {
			return finish()
		}

		let a = character(at: currentPosition)

		guard a == 0x2C else {
			return finish()
		}

		commaEaten = true
		currentPosition += 1

		guard currentPosition + 6 <= selfLength else {
			return finish()
		}

		let backgroundCandidate = substring(with: NSRange(location: currentPosition, length: 6)) as NSString

		if backgroundCandidate.onlyContainsCharacters(from: NSCharacterSet.hexadecimal as CharacterSet) {
			mBackgroundColor = backgroundCandidate as String
			currentPosition += 6
		}

		return finish()
	}

	private func colorAsDigit(
		startingAt rangeStart: UInt,
		foregroundColor: inout NSNumber?,
		backgroundColor: inout NSNumber?
	) -> UInt {
		let selfLength = length
		precondition(Int(rangeStart) < selfLength)

		var currentPosition = Int(rangeStart)
		var mForegroundColor = NSNotFound
		var mBackgroundColor = NSNotFound
		var commaEaten = false

		currentPosition += 1

		func finish() -> UInt {
			if mBackgroundColor == NSNotFound, commaEaten {
				currentPosition -= 1
			}

			if mForegroundColor != NSNotFound,
				mForegroundColor <= Int(IRCTextFormatterEffectColorHighestDigit)
			{
				foregroundColor = NSNumber(value: mForegroundColor)
			}

			if mBackgroundColor != NSNotFound,
				mBackgroundColor <= Int(IRCTextFormatterEffectColorHighestDigit)
			{
				backgroundColor = NSNumber(value: mBackgroundColor)
			}

			return UInt(currentPosition - Int(rangeStart))
		}

		guard currentPosition < selfLength else {
			return finish()
		}

		let a = character(at: currentPosition)

		guard isBase10Numeric(a) else {
			return finish()
		}

		mForegroundColor = Int(a - 0x30)
		currentPosition += 1

		guard currentPosition < selfLength else {
			return finish()
		}

		let b = character(at: currentPosition)

		if isBase10Numeric(b) {
			mForegroundColor = mForegroundColor * 10 + Int(b - 0x30)
			currentPosition += 1
		}

		guard currentPosition < selfLength else {
			return finish()
		}

		let c = character(at: currentPosition)

		guard c == 0x2C else {
			return finish()
		}

		commaEaten = true
		currentPosition += 1

		guard currentPosition < selfLength else {
			return finish()
		}

		let d = character(at: currentPosition)

		guard isBase10Numeric(d) else {
			return finish()
		}

		mBackgroundColor = Int(d - 0x30)
		currentPosition += 1

		guard currentPosition < selfLength else {
			return finish()
		}

		let e = character(at: currentPosition)

		guard isBase10Numeric(e) else {
			return finish()
		}

		mBackgroundColor = mBackgroundColor * 10 + Int(e - 0x30)
		currentPosition += 1

		return finish()
	}

	@objc(base64EncodingWithLineLength:)
	public func base64Encoding(withLineLength lineLength: UInt) -> [String] {
		guard length > 0 else {
			return [self as String]
		}

		guard let selfData = data(using: String.Encoding.utf8.rawValue) else {
			return [self as String]
		}

		let encodedString = selfData.base64EncodedString(options: []) as NSString
		return encodedString.split(withMaximumLength: lineLength) as? [String] ?? [encodedString as String]
	}

	@objc(padNicknameWithCharacter:maximumLength:)
	public func padNickname(withCharacter padCharacter: unichar, maximumLength: UInt) -> String? {
		precondition(padCharacter != 0)
		precondition(maximumLength > 0)

		let padCharacterString = String(utf16CodeUnits: [padCharacter], count: 1)

		if length < Int(maximumLength) {
			return (self as String) + padCharacterString
		}

		let substring = substring(to: Int(maximumLength)) as NSString

		for i in stride(from: substring.length - 1, through: 0, by: -1) {
			let substringCharacter = substring.character(at: i)

			if substringCharacter == padCharacter {
				continue
			}

			let stringHead = substring.substring(to: i)
			var stringHeadMutable = stringHead

			for _ in i..<substring.length {
				stringHeadMutable += "_"
			}

			return stringHeadMutable
		}

		return nil
	}

	@objc public var encodedMessageTagString: String {
		guard length > 0 else {
			return self as String
		}

		let bob = NSMutableString(string: self as String)
		let fullRange = bob.range

		bob.replaceOccurrences(of: "\\", with: "\\\\", options: [], range: fullRange)
		bob.replaceOccurrences(of: ";", with: "\\:", options: [], range: bob.range)
		bob.replaceOccurrences(of: " ", with: "\\s", options: [], range: bob.range)
		bob.replaceOccurrences(of: "\r", with: "\\r", options: [], range: bob.range)
		bob.replaceOccurrences(of: "\n", with: "\\n", options: [], range: bob.range)

		return bob as String
	}

	@objc public var decodedMessageTagString: String {
		let length = self.length

		guard length > 0 else {
			return self as String
		}

		var inputBuffer = [UniChar](repeating: 0, count: length)
		var outputBuffer = [UniChar](repeating: 0, count: length)

		getCharacters(&inputBuffer, range: NSRange(location: 0, length: length))

		var outputLength = 0
		var i = 0

		while i < length {
			let character = inputBuffer[i]

			if character != 0x5C {
				outputBuffer[outputLength] = character
				outputLength += 1
				i += 1
				continue
			}

			if i + 1 >= length {
				break
			}

			i += 1
			let next = inputBuffer[i]

			switch next {
			case 0x3A:
				outputBuffer[outputLength] = 0x3B
			case 0x73:
				outputBuffer[outputLength] = 0x20
			case 0x5C:
				outputBuffer[outputLength] = 0x5C
			case 0x72:
				outputBuffer[outputLength] = 0x0D
			case 0x6E:
				outputBuffer[outputLength] = 0x0A
			default:
				outputBuffer[outputLength] = next
			}

			outputLength += 1
			i += 1
		}

		return NSString(characters: outputBuffer, length: outputLength) as String
	}

	@objc(isModeSymbol)
	public var isModeSymbol: Bool {
		guard length == 1 else {
			return false
		}

		guard let scalar = UnicodeScalar(character(at: 0)) else {
			return false
		}

		return NSCharacterSet.atoZ.contains(scalar)
	}
}
