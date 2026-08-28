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
import CocoaExtensions
import GlasstualPluginKit

private nonisolated func isBase10Numeric(_ character: unichar) -> Bool {
	character >= 0x30 && character <= 0x39
}

private nonisolated let defaultHostmaskNicknameLength = 50

@MainActor
private func maximumHostmaskNicknameLength(on client: IRCClient?) -> Int {
	guard let client, client.isConnectedToZNC == false, client.supportInfo.configurationReceived else {
		return defaultHostmaskNicknameLength
	}

	let configuredMaximum = Int(client.supportInfo.maximumNicknameLength)
	return configuredMaximum > 0 ? configuredMaximum : defaultHostmaskNicknameLength
}

public nonisolated extension NSString {
	@objc(isValidInternetAddress)
	var isValidInternetAddress: Bool {
		guard length > 0 else {
			return false
		}

		if (self as String).isIPAddress || isEqual(to: "localhost") {
			return true
		}

		return (self as String).onlyContainsCharacters(from: .textualAlphanumericDashPeriod)
	}

	@objc(isValidInternetPort)
	var isValidInternetPort: Bool {
		guard let value = Int(self as String) else {
			return false
		}

		return value.isValidInternetPort
	}

	@objc var stringByAppendingIRCFormattingStop: String {
		(self as String) + String(utf16CodeUnits: [UniChar(IRCTextFormatterControlCharacter.terminator)], count: 1)
	}

	/// The receiver parsed as `nickname!username@address`, or `nil` when it is
	/// not a hostmask. Nickname length is bounded by the protocol default.
	var hostmask: IRCHostmask? {
		IRCHostmask(parsing: self as String, maximumNicknameLength: defaultHostmaskNicknameLength)
	}

	/// The receiver parsed as a hostmask, bounding the nickname by whatever
	/// length `client` advertised in its ISUPPORT.
	@MainActor
	func hostmask(on client: IRCClient?) -> IRCHostmask? {
		IRCHostmask(
			parsing: self as String,
			maximumNicknameLength: maximumHostmaskNicknameLength(on: client)
		)
	}

	@objc(isHostmask)
	var isHostmask: Bool {
		hostmask != nil
	}

	@objc(isHostmaskAddress)
	var isHostmaskAddress: Bool {
		isHostmaskAddress(on: nil)
	}

	@objc(isHostmaskAddressOn:)
	func isHostmaskAddress(on _: IRCClient?) -> Bool {
		IRCHostmask.isValidAddress(self as String)
	}

	@objc(isHostmaskUsername)
	var isHostmaskUsername: Bool {
		isHostmaskUsername(on: nil)
	}

	@objc(isHostmaskUsernameOn:)
	func isHostmaskUsername(on _: IRCClient?) -> Bool {
		IRCHostmask.isValidUsername(self as String)
	}

	@objc(isHostmaskNickname)
	var isHostmaskNickname: Bool {
		IRCHostmask.isValidNickname(self as String, maximumLength: defaultHostmaskNicknameLength)
	}

	@objc(isHostmaskNicknameOn:)
	@MainActor
	func isHostmaskNickname(on client: IRCClient?) -> Bool {
		IRCHostmask.isValidNickname(
			self as String,
			maximumLength: maximumHostmaskNicknameLength(on: client)
		)
	}

	@objc(isChannelNameOn:)
	@MainActor
	func isChannelName(on client: IRCClient) -> Bool {
		guard length > 0 else {
			return false
		}

		let channelNamePrefixes = client.supportInfo.channelNamePrefixes
		let channelName = self as String
		let firstCharacter = String(channelName.prefix(1))

		return channelName.hasPrefix("~#") || channelNamePrefixes.contains(firstCharacter)
	}

	@objc(isChannelName)
	var isChannelName: Bool {
		guard length > 0 else {
			return false
		}

		let firstCharacter = character(at: 0)
		return firstCharacter == 0x23 || firstCharacter == 0x26 || firstCharacter == 0x2B
			|| firstCharacter == 0x21 || firstCharacter == 0x7E || firstCharacter == 0x3F
	}

	@objc var channelNameWithoutBang: String? {
		guard isChannelName else {
			return self as String
		}

		return substring(from: 1)
	}

	@objc(channelNameWithoutBangOn:)
	@MainActor
	func channelNameWithoutBang(on client: IRCClient) -> String? {
		guard isChannelName(on: client) else {
			return self as String
		}

		guard length >= 2 else {
			return self as String
		}

		let channelNamePrefixes = client.supportInfo.channelNamePrefixes
		let character = String((self as String).prefix(1))

		if channelNamePrefixes.contains(character) {
			return substring(from: 1)
		}

		return self as String
	}

	@objc var nicknameFromHostmask: String? {
		hostmask?.nickname ?? (self as String)
	}

	@objc var usernameFromHostmask: String? {
		hostmask?.username
	}

	@objc var addressFromHostmask: String? {
		hostmask?.address
	}

	@objc var stringWithValidURIScheme: String? {
		LinkParser.urlWithProperScheme(self as String)
	}

	@objc(attributedStringWithIRCFormatting:preferredFontColor:honorFormattingPreference:)
	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?,
		honorFormattingPreference formattingPreference: Bool
	) -> NSAttributedString? {
		if formattingPreference, TextualPreferences.removeAllFormatting() {
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
	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?
	) -> NSAttributedString? {
		attributedString(
			withIRCFormatting: preferredFont,
			preferredFontColor: preferredFontColor,
			honorFormattingPreference: false
		)
	}

	@objc var stripIRCEffects: String {
		IRCFormatting.removingControlCodes(from: self as String)
	}

	@objc(colorComponentsOfCharacter:startingAt:foregroundColor:backgroundColor:)
	func colorComponents(
		ofCharacter character: unichar,
		startingAt rangeStart: UInt,
		foregroundColor: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
		backgroundColor: AutoreleasingUnsafeMutablePointer<AnyObject?>?
	) -> UInt {
		if character == UniChar(IRCTextFormatterControlCharacter.colorDigit) {
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

		if character == UniChar(IRCTextFormatterControlCharacter.colorHex) {
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
				foregroundColor = NSColor.textual_color(hexadecimalValue: mForegroundColor.uppercased())
			}

			if let mBackgroundColor {
				backgroundColor = NSColor.textual_color(hexadecimalValue: mBackgroundColor.uppercased())
			}

			return UInt(currentPosition - Int(rangeStart))
		}

		guard currentPosition + 6 <= selfLength else {
			return finish()
		}

		let foregroundCandidate = substring(with: NSRange(location: currentPosition, length: 6))

		if foregroundCandidate.onlyContainsCharacters(from: .textualHexadecimal) {
			mForegroundColor = foregroundCandidate
			currentPosition += 6
		} else {
			return finish()
		}

		guard currentPosition < selfLength else {
			return finish()
		}

		let separator = character(at: currentPosition)

		guard separator == 0x2C else {
			return finish()
		}

		commaEaten = true
		currentPosition += 1

		guard currentPosition + 6 <= selfLength else {
			return finish()
		}

		let backgroundCandidate = substring(with: NSRange(location: currentPosition, length: 6))

		if backgroundCandidate.onlyContainsCharacters(from: .textualHexadecimal) {
			mBackgroundColor = backgroundCandidate
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
			   mForegroundColor <= Int(IRCTextFormatterColor.maximumPaletteIndex)
			{
				foregroundColor = NSNumber(value: mForegroundColor)
			}

			if mBackgroundColor != NSNotFound,
			   mBackgroundColor <= Int(IRCTextFormatterColor.maximumPaletteIndex)
			{
				backgroundColor = NSNumber(value: mBackgroundColor)
			}

			return UInt(currentPosition - Int(rangeStart))
		}

		guard currentPosition < selfLength else {
			return finish()
		}

		let firstForegroundDigit = character(at: currentPosition)

		guard isBase10Numeric(firstForegroundDigit) else {
			return finish()
		}

		mForegroundColor = Int(firstForegroundDigit - 0x30)
		currentPosition += 1

		guard currentPosition < selfLength else {
			return finish()
		}

		let secondForegroundDigit = character(at: currentPosition)

		if isBase10Numeric(secondForegroundDigit) {
			mForegroundColor = mForegroundColor * 10 + Int(secondForegroundDigit - 0x30)
			currentPosition += 1
		}

		guard currentPosition < selfLength else {
			return finish()
		}

		let separator = character(at: currentPosition)

		guard separator == 0x2C else {
			return finish()
		}

		commaEaten = true
		currentPosition += 1

		guard currentPosition < selfLength else {
			return finish()
		}

		let firstBackgroundDigit = character(at: currentPosition)

		guard isBase10Numeric(firstBackgroundDigit) else {
			return finish()
		}

		mBackgroundColor = Int(firstBackgroundDigit - 0x30)
		currentPosition += 1

		guard currentPosition < selfLength else {
			return finish()
		}

		let secondBackgroundDigit = character(at: currentPosition)

		guard isBase10Numeric(secondBackgroundDigit) else {
			return finish()
		}

		mBackgroundColor = mBackgroundColor * 10 + Int(secondBackgroundDigit - 0x30)
		currentPosition += 1

		return finish()
	}

	@objc(base64EncodingWithLineLength:)
	func base64Encoding(withLineLength lineLength: UInt) -> [String] {
		guard length > 0 else {
			return [self as String]
		}

		guard let selfData = data(using: String.Encoding.utf8.rawValue), lineLength > 0 else {
			return [self as String]
		}

		/* Base64 output is pure ASCII, so chunking it by character count and by
		 byte count are the same thing and neither can split a character. */
		let encodedString = selfData.base64EncodedString(options: [])
		return stride(from: 0, to: encodedString.count, by: Int(lineLength)).map { offset in
			String(encodedString.dropFirst(offset).prefix(Int(lineLength)))
		}
	}

	@objc(padNicknameWithCharacter:maximumLength:)
	func padNickname(withCharacter padCharacter: unichar, maximumLength: UInt) -> String? {
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

			for _ in i ..< substring.length {
				stringHeadMutable += "_"
			}

			return stringHeadMutable
		}

		return nil
	}

	@objc var encodedMessageTagString: String {
		guard length > 0 else {
			return self as String
		}

		return (self as String)
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: ";", with: "\\:")
			.replacingOccurrences(of: " ", with: "\\s")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\n", with: "\\n")
	}

	@objc var decodedMessageTagString: String {
		let length = length

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
	var isModeSymbol: Bool {
		guard length == 1 else {
			return false
		}

		guard let scalar = UnicodeScalar(character(at: 0)) else {
			return false
		}

		return CharacterSet.textualLetter.contains(scalar)
	}
}
