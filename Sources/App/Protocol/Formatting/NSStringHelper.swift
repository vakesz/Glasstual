/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

// AppKit: nickname colouring and the formatting helpers below build attributed
// strings out of NSColor and NSFont.
import AppKit
import CocoaExtensions
import GlasstualPluginKit

private nonisolated func isBase10Numeric(_ character: unichar) -> Bool { // nonisolated: pure
	character >= 0x30 && character <= 0x39
}

private nonisolated let defaultHostmaskNicknameLength = 50 // nonisolated: let

@MainActor
private func maximumHostmaskNicknameLength(on client: IRCClient?) -> Int {
	guard let client, client.isConnectedToZNC == false, client.supportInfo.configurationReceived else {
		return defaultHostmaskNicknameLength
	}

	let configuredMaximum = Int(client.supportInfo.maximumNicknameLength)
	return configuredMaximum > 0 ? configuredMaximum : defaultHostmaskNicknameLength
}

/// A colour named by an IRC colour control code.
public nonisolated enum IRCColor: Sendable { // nonisolated: value
	/// An mIRC palette index.
	case palette(Int)
	/// A literal colour from a hexadecimal control code.
	case rgb(NSColor)

	/// The value the renderer stores as a text attribute.
	public var attributeValue: AnyObject {
		switch self {
		case let .palette(index): NSNumber(value: index)
		case let .rgb(color): color
		}
	}
}

/// What one colour control code says.
public nonisolated struct IRCColorComponents: Sendable { // nonisolated: value
	public let foreground: IRCColor?
	public let background: IRCColor?
	/// How many characters of the control code were read.
	public let charactersConsumed: Int
}

public nonisolated extension NSString { // nonisolated: pure
	var isValidInternetAddress: Bool {
		guard length > 0 else {
			return false
		}

		if (self as String).isIPAddress || isEqual(to: "localhost") {
			return true
		}

		return (self as String).onlyContainsCharacters(from: .textualAlphanumericDashPeriod)
	}

	var isValidInternetPort: Bool {
		guard let value = Int(self as String) else {
			return false
		}

		return value.isValidInternetPort
	}

	var stringByAppendingIRCFormattingStop: String {
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

	/// The receiver read as an RFC 2812 2.3.1 message prefix, or `nil` when it
	/// names a server rather than a user.
	@MainActor
	func senderPrefix(on client: IRCClient?) -> Prefix? {
		Prefix.user(
			parsing: self as String,
			maximumNicknameLength: maximumHostmaskNicknameLength(on: client)
		)
	}

	var isHostmask: Bool {
		hostmask != nil
	}

	var isHostmaskAddress: Bool {
		isHostmaskAddress(on: nil)
	}

	func isHostmaskAddress(on _: IRCClient?) -> Bool {
		IRCHostmask.isValidAddress(self as String)
	}

	var isHostmaskUsername: Bool {
		isHostmaskUsername(on: nil)
	}

	func isHostmaskUsername(on _: IRCClient?) -> Bool {
		IRCHostmask.isValidUsername(self as String)
	}

	var isHostmaskNickname: Bool {
		IRCHostmask.isValidNickname(self as String, maximumLength: defaultHostmaskNicknameLength)
	}

	@MainActor
	func isHostmaskNickname(on client: IRCClient?) -> Bool {
		IRCHostmask.isValidNickname(
			self as String,
			maximumLength: maximumHostmaskNicknameLength(on: client)
		)
	}

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

	var isChannelName: Bool {
		guard length > 0 else {
			return false
		}

		let firstCharacter = character(at: 0)
		return firstCharacter == 0x23 || firstCharacter == 0x26 || firstCharacter == 0x2B
			|| firstCharacter == 0x21 || firstCharacter == 0x7E || firstCharacter == 0x3F
	}

	var channelNameWithoutBang: String? {
		guard isChannelName else {
			return self as String
		}

		return substring(from: 1)
	}

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

	var nicknameFromHostmask: String? {
		hostmask?.nickname ?? (self as String)
	}

	var usernameFromHostmask: String? {
		hostmask?.username
	}

	var addressFromHostmask: String? {
		hostmask?.address
	}

	/// Main-actor: it reads a preference the main actor owns and it renders
	/// with `NSFont`/`NSColor`, which is what every caller hands it anyway.
	@MainActor
	func attributedString(
		withIRCFormatting preferredFont: NSFont,
		preferredFontColor: NSColor?,
		honorFormattingPreference formattingPreference: Bool
	) -> NSAttributedString? {
		if formattingPreference, Preferences.Messages.removeAllFormatting.value {
			return NSAttributedString(string: stripIRCEffects)
		}

		var attributes = LogRendererConfiguration()

		attributes[.preferredFont] = preferredFont

		if let preferredFontColor {
			attributes[.preferredFontColor] = preferredFontColor
		}

		return LogRenderer.renderBody(asAttributedString: self as String, withAttributes: attributes)
	}

	@MainActor
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

	var stripIRCEffects: String {
		IRCFormatting.removingControlCodes(from: self as String)
	}

	/// The colours a colour control code names, and how many characters of the
	/// code were read.
	///
	/// A digit code names palette indices and a hex code names literal colours;
	/// they used to be written through one `AnyObject?` out-parameter each, so
	/// which kind arrived was not knowable at the call site.
	func colorComponents(ofCharacter character: unichar, startingAt rangeStart: UInt) -> IRCColorComponents {
		if character == UniChar(IRCTextFormatterControlCharacter.colorDigit) {
			var foregroundNumber: NSNumber?
			var backgroundNumber: NSNumber?

			let consumed = colorAsDigit(
				startingAt: rangeStart,
				foregroundColor: &foregroundNumber,
				backgroundColor: &backgroundNumber
			)

			return IRCColorComponents(
				foreground: foregroundNumber.map { .palette($0.intValue) },
				background: backgroundNumber.map { .palette($0.intValue) },
				charactersConsumed: Int(consumed)
			)
		}

		if character == UniChar(IRCTextFormatterControlCharacter.colorHex) {
			var foregroundNSColor: NSColor?
			var backgroundNSColor: NSColor?

			let consumed = colorAsHex(
				startingAt: rangeStart,
				foregroundColor: &foregroundNSColor,
				backgroundColor: &backgroundNSColor
			)

			return IRCColorComponents(
				foreground: foregroundNSColor.map { .rgb($0) },
				background: backgroundNSColor.map { .rgb($0) },
				charactersConsumed: Int(consumed)
			)
		}

		return IRCColorComponents(foreground: nil, background: nil, charactersConsumed: 0)
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

			/* The tail used to be hardcoded to "_" while the head branch above
			 used the caller's character. The sole caller passes "_", so the two
			 agreed by accident. */
			var stringHeadMutable = substring.substring(to: i)

			for _ in i ..< substring.length {
				stringHeadMutable += padCharacterString
			}

			return stringHeadMutable
		}

		return nil
	}

	var encodedMessageTagString: String {
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

	var decodedMessageTagString: String {
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
