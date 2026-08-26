/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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
 *
 *********************************************************************** */

/* A portion of this source file contains copyrighted work derived from one or
 more 3rd party, open source projects. The use of this work is hereby
 acknowledged. */

/*
 The New BSD License

 Copyright (c) 2008 - 2010 Satoshi Nakagawa < psychs AT limechat DOT net >
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.
 */

import CryptoKit
import Foundation

private enum UTF16StringOperations {
	static let notFound = -1

	static func hexadecimalString(for digest: some Sequence<UInt8>) -> String {
		digest.map { String(format: "%02x", $0) }.joined()
	}

	static func position(
		of needle: String,
		in source: NSString,
		options: NSString.CompareOptions
	) -> Int {
		guard source.length > 0 else {
			return notFound
		}

		let result = source.range(of: needle, options: options)
		return result.location == NSNotFound ? notFound : result.location
	}

	static func enumerateMatches(
		of needle: String,
		in source: NSString,
		options: NSString.CompareOptions,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		var searchLength = source.length
		guard searchLength > 0 else {
			return
		}

		let searchesBackwards = options.contains(.backwards)
		var currentPosition = 0

		while !searchesBackwards && currentPosition < searchLength || searchesBackwards && searchLength > 0 {
			let range = source.range(
				of: needle,
				options: options,
				range: NSRange(location: currentPosition, length: searchLength - currentPosition)
			)
			guard range.location != NSNotFound else {
				break
			}

			var stop = ObjCBool(false)
			body(range, &stop)
			guard !stop.boolValue else {
				break
			}

			if searchesBackwards {
				searchLength = range.location
			} else {
				currentPosition = NSMaxRange(range)
			}
		}
	}

	static func replacingCharacters(
		in source: NSString,
		from characterSet: CharacterSet,
		with replacement: String
	) -> NSString {
		guard source.length > 0 else {
			return source
		}

		var mutableSource: NSMutableString?
		for index in stride(from: source.length - 1, through: 0, by: -1) {
			guard
				let scalar = Unicode.Scalar(source.character(at: index)),
				characterSet.contains(scalar)
			else {
				continue
			}

			if mutableSource == nil {
				mutableSource = NSMutableString(string: source)
			}
			mutableSource?.replaceCharacters(in: NSRange(location: index, length: 1), with: replacement)
		}

		return mutableSource.map(NSString.init(string:)) ?? source
	}

	static func addressBytes(_ source: NSString, family: Int32) -> Data? {
		guard source.length > 0, let cString = source.utf8String else {
			return nil
		}

		if family == AF_INET {
			var address = in_addr()
			guard inet_pton(AF_INET, cString, &address) == 1 else {
				return nil
			}
			return Data(bytes: &address.s_addr, count: MemoryLayout.size(ofValue: address.s_addr))
		}

		var address = in6_addr()
		guard inet_pton(AF_INET6, cString, &address) == 1 else {
			return nil
		}
		return Data(bytes: &address, count: MemoryLayout.size(ofValue: address))
	}
}

public extension NSString {
	@objc(stringWithBytes:length:encoding:)
	class func ce_string(
		bytes: UnsafeRawPointer,
		length: UInt,
		encoding: UInt
	) -> NSString? {
		NSString(bytes: bytes, length: Int(length), encoding: encoding)
	}

	@objc(stringWithData:encoding:)
	class func ce_string(data: Data, encoding: UInt) -> NSString? {
		NSString(data: data, encoding: encoding)
	}

	@objc(range)
	var ce_range: NSRange {
		NSRange(location: 0, length: length)
	}

	@objc(stringWithUUID)
	class func ce_stringWithUUID() -> NSString {
		UUID().uuidString as NSString
	}

	@objc(charsetRepFromStringEncoding:)
	class func ce_charsetRepresentation(from encoding: UInt) -> NSString? {
		let coreFoundationEncoding = CFStringConvertNSStringEncodingToEncoding(encoding)
		return CFStringConvertEncodingToIANACharSetName(coreFoundationEncoding)
	}

	@objc(supportedStringEncodingsWithTitle:)
	class func ce_supportedStringEncodingsWithTitle(_ favorUTF8: Bool) -> [String: NSNumber] {
		var result: [String: NSNumber] = [:]
		for encoding in ce_supportedStringEncodings(favorUTF8) {
			let rawValue = encoding.uintValue
			result[localizedName(of: rawValue)] = encoding
		}
		return result
	}

	@objc(supportedStringEncodings:)
	class func ce_supportedStringEncodings(_ favorUTF8: Bool) -> [NSNumber] {
		var result: [NSNumber] = []
		if favorUTF8 {
			result.append(NSNumber(value: String.Encoding.utf8.rawValue))
		}

		var encodings = availableStringEncodings
		while encodings.pointee != 0 {
			let encoding = encodings.pointee
			if !favorUTF8 || encoding != String.Encoding.utf8.rawValue {
				result.append(NSNumber(value: encoding))
			}
			encodings = encodings.advanced(by: 1)
		}
		return result
	}

	@objc(stringCharacterAtIndex:)
	func ce_stringCharacter(at index: UInt) -> NSString {
		var character = character(at: Int(index))
		return NSString(characters: &character, length: 1)
	}

	@objc(substringAfterIndex:)
	func ce_substring(after index: UInt) -> NSString {
		substring(from: Int(index) + 1) as NSString
	}

	@objc(substringAtIndex:toLength:)
	func ce_substring(at index: Int, toLength requestedLength: Int) -> NSString {
		if index >= 0, requestedLength >= 0 {
			return substring(with: NSRange(location: index, length: requestedLength)) as NSString
		}

		let sourceLength = length
		let location: Int
		let resultLength: Int
		if index < 0, requestedLength < 0 {
			location = -index
			resultLength = index + requestedLength + sourceLength
		} else if index < 0 {
			location = 0
			resultLength = sourceLength + index
		} else {
			location = sourceLength + requestedLength
			resultLength = -requestedLength
		}

		precondition((0 ... sourceLength).contains(location), "Location is out of range")
		precondition((0 ... sourceLength).contains(resultLength), "Length is out of range")
		return substring(with: NSRange(location: location, length: resultLength)) as NSString
	}

	@objc(substringFromIndex:toIndex:)
	func ce_substring(from startIndex: UInt, to endIndex: UInt) -> NSString {
		precondition(startIndex <= endIndex)
		return substring(
			with: NSRange(location: Int(startIndex), length: Int(endIndex - startIndex))
		) as NSString
	}

	@objc(isEqualToStringIgnoringCase:)
	func ce_isEqualToStringIgnoringCase(_ other: String) -> Bool {
		self === other as NSString || caseInsensitiveCompare(other) == .orderedSame
	}

	@objc(contains:)
	func ce_contains(_ string: String) -> Bool {
		ce_stringPosition(string) >= 0
	}

	@objc(containsIgnoringCase:)
	func ce_containsIgnoringCase(_ string: String) -> Bool {
		ce_stringPositionIgnoringCase(string) >= 0
	}

	@objc(characterStringBuffer)
	var ce_characterStringBuffer: [String] {
		guard length > 0 else {
			return []
		}

		var result: [String] = []
		enumerateSubstrings(
			in: NSRange(location: 0, length: length),
			options: .byComposedCharacterSequences
		) { substring, _, _, _ in
			if let substring {
				result.append(substring)
			}
		}
		return result
	}

	@objc(sha1)
	var ce_sha1: String? {
		guard let data = data(using: String.Encoding.utf8.rawValue) else {
			return nil
		}
		return UTF16StringOperations.hexadecimalString(for: Insecure.SHA1.hash(data: data))
	}

	@objc(sha256)
	var ce_sha256: String? {
		guard let data = data(using: String.Encoding.utf8.rawValue) else {
			return nil
		}
		return UTF16StringOperations.hexadecimalString(for: SHA256.hash(data: data))
	}

	@objc(sha512)
	var ce_sha512: String? {
		guard let data = data(using: String.Encoding.utf8.rawValue) else {
			return nil
		}
		return UTF16StringOperations.hexadecimalString(for: SHA512.hash(data: data))
	}

	@objc(split:)
	func ce_split(_ delimiter: String) -> [String] {
		components(separatedBy: delimiter)
	}

	@objc(enumerateSplitWithCharacterSet:withBlock:)
	func ce_enumerateSplit(
		with characterSet: CharacterSet,
		using body: (String, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		for sequence in components(separatedBy: characterSet) {
			var stop = ObjCBool(false)
			body(sequence, &stop)
			if stop.boolValue {
				break
			}
		}
	}

	@objc(enumerateSplitOnNewLinesWithBlock:)
	func ce_enumerateSplitOnNewLines(
		_ body: (String, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		ce_enumerateSplit(with: .newlines, using: body)
	}

	@objc(splitWithMaximumLength:)
	func ce_split(maximumLength: UInt) -> [String] {
		precondition(maximumLength > 0)
		guard length > 0 else {
			return []
		}
		guard length > maximumLength else {
			return [self as String]
		}

		var result: [String] = []
		var processedLength = 0
		while processedLength < length {
			let remainingLength = min(Int(maximumLength), length - processedLength)
			result.append(substring(with: NSRange(location: processedLength, length: remainingLength)))
			processedLength += remainingLength
		}
		return result
	}

	@objc(trim)
	var ce_trim: NSString {
		trimmingCharacters(in: .whitespacesAndNewlines) as NSString
	}

	@objc(trimCharacters:)
	func ce_trim(characters: String) -> NSString {
		trimmingCharacters(in: CharacterSet(charactersIn: characters)) as NSString
	}

	@objc(removeAllNewlines)
	var ce_removeAllNewlines: NSString {
		UTF16StringOperations.replacingCharacters(in: self, from: .newlines, with: "")
	}

	@objc(stringByReplacingOccurrencesOfCharacterSet:withString:)
	func ce_replacingCharacters(in characterSet: CharacterSet, with replacement: String) -> NSString {
		UTF16StringOperations.replacingCharacters(in: self, from: characterSet, with: replacement)
	}

	@objc(hasPrefixIgnoringCase:)
	func ce_hasPrefixIgnoringCase(_ string: String) -> Bool {
		let range = range(of: string, options: [.anchored, .literal, .caseInsensitive])
		return range.location == 0 && range.length > 0
	}

	@objc(hasSuffixWithCharacterSet:)
	func ce_hasSuffix(with characterSet: CharacterSet) -> Bool {
		let range = rangeOfCharacter(from: characterSet, options: [.anchored, .backwards])
		return range.location != NSNotFound && NSMaxRange(range) == length
	}

	@objc(compareWithWord:lengthPenaltyWeight:)
	func ce_compare(with word: String, lengthPenaltyWeight weight: CGFloat) -> CGFloat {
		let candidate = word as NSString
		guard candidate.length > 0, candidate.length <= length else {
			return 0
		}

		let source = lowercased as NSString
		let lowercasedCandidate = candidate.lowercased as NSString
		var commonCharacterCount = 0
		var startPosition = 0
		var distancePenalty: CGFloat = 0

		for candidateIndex in 0 ..< lowercasedCandidate.length {
			var matchPosition: Int?
			for sourceIndex in startPosition ..< source.length
				where lowercasedCandidate.character(at: candidateIndex) == source.character(at: sourceIndex)
			{
				matchPosition = sourceIndex
				break
			}

			guard let matchPosition else {
				return 0
			}

			let distance = matchPosition - startPosition
			if distance > 0 {
				distancePenalty += CGFloat(distance - 1) / CGFloat(distance)
			}
			commonCharacterCount += 1
			startPosition = matchPosition + 1
		}

		let lengthPenalty = 1 - CGFloat(lowercasedCandidate.length) / CGFloat(source.length)
		return CGFloat(commonCharacterCount) - distancePenalty - weight * lengthPenalty
	}

	@objc(stringPosition:options:)
	func ce_stringPosition(_ needle: String, options: NSString.CompareOptions) -> Int {
		UTF16StringOperations.position(of: needle, in: self, options: options)
	}

	@objc(stringPosition:)
	func ce_stringPosition(_ needle: String) -> Int {
		ce_stringPosition(needle, options: .literal)
	}

	@objc(stringPositionIgnoringCase:)
	func ce_stringPositionIgnoringCase(_ needle: String) -> Int {
		ce_stringPosition(needle, options: [.literal, .caseInsensitive])
	}

	@objc(enumerateMatchesOfString:withBlock:)
	func ce_enumerateMatches(
		of string: String,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		ce_enumerateMatches(of: string, using: body, options: [])
	}

	@objc(enumerateMatchesOfString:withBlock:options:)
	func ce_enumerateMatches(
		of string: String,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void,
		options: NSString.CompareOptions
	) {
		UTF16StringOperations.enumerateMatches(of: string, in: self, options: options, using: body)
	}

	@objc(enumerateMatchesOfRegularExpression:withBlock:)
	func ce_enumerateMatches(
		ofRegularExpression expression: String,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		ce_enumerateMatches(ofRegularExpression: expression, using: body, options: [])
	}

	@objc(enumerateMatchesOfRegularExpression:withBlock:options:)
	func ce_enumerateMatches(
		ofRegularExpression expression: String,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void,
		options: NSString.CompareOptions
	) {
		ce_enumerateMatches(of: expression, using: body, options: options.union(.regularExpression))
	}

	@objc(enumerateFirstOccurrenceOfCharactersInString:withBlock:)
	func ce_enumerateFirstOccurrences(
		ofCharactersIn string: String,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		ce_enumerateFirstOccurrences(ofCharactersIn: string, using: body, options: [])
	}

	@objc(enumerateFirstOccurrenceOfCharactersInString:withBlock:options:)
	func ce_enumerateFirstOccurrences(
		ofCharactersIn string: String,
		using body: (NSRange, UnsafeMutablePointer<ObjCBool>) -> Void,
		options: NSString.CompareOptions
	) {
		var searchLength = length
		guard searchLength > 0 else {
			return
		}

		let searchesBackwards = options.contains(.backwards)
		var currentPosition = 0
		for character in (string as NSString).ce_characterStringBuffer {
			let range = range(
				of: character,
				options: options,
				range: NSRange(location: currentPosition, length: searchLength - currentPosition)
			)
			guard range.location != NSNotFound else {
				break
			}

			var stop = ObjCBool(false)
			body(range, &stop)
			guard !stop.boolValue else {
				break
			}

			if searchesBackwards {
				searchLength = range.location
			} else {
				currentPosition = NSMaxRange(range)
			}
		}
	}

	@objc(isIPAddress)
	var ce_isIPAddress: Bool {
		ce_isIPv4Address || ce_isIPv6Address
	}

	@objc(isIPv4Address)
	var ce_isIPv4Address: Bool {
		ce_IPv4AddressBytes != nil
	}

	@objc(isIPv6Address)
	var ce_isIPv6Address: Bool {
		ce_IPv6AddressBytes != nil
	}

	@objc(IPv4AddressBytes)
	var ce_IPv4AddressBytes: Data? {
		UTF16StringOperations.addressBytes(self, family: AF_INET)
	}

	@objc(IPv6AddressBytes)
	var ce_IPv6AddressBytes: Data? {
		UTF16StringOperations.addressBytes(self, family: AF_INET6)
	}

	@objc(safeFilename)
	var ce_safeFilename: NSString {
		guard length > 0 else {
			return self
		}

		var result = ce_trim.replacingOccurrences(of: "/", with: "_")
		result = result.replacingOccurrences(of: ":", with: "_")
		if UserDefaults.standard.bool(forKey: "Cocoa Extensions Framework -> Exclude Bars from Safe Filenames") {
			result = result.replacingOccurrences(of: "|", with: "_")
		}
		return result as NSString
	}

	@objc(occurrencesOfCharacter:)
	func ce_occurrences(of character: unichar) -> UInt {
		var count = 0
		for index in 0 ..< length where self.character(at: index) == character {
			count += 1
		}
		return UInt(count)
	}

	@objc(isPositiveWholeNumber)
	var ce_isPositiveWholeNumber: Bool {
		ce_contentsIsOfType([.wholeNumber, .positiveNumber])
	}

	@objc(isNumericOnly)
	var ce_isNumericOnly: Bool {
		ce_contentsIsOfType([.wholeNumber, .positiveNumber])
	}

	@objc(isAlphabeticNumericOnly)
	var ce_isAlphabeticNumericOnly: Bool {
		ce_contentsIsOfType([.wholeNumber, .positiveNumber, .alphabetic])
	}

	@objc(contentsIsOfType:)
	func ce_contentsIsOfType(_ type: CSStringType) -> Bool {
		guard length > 0 else {
			return false
		}
		if type == .any {
			return true
		}

		let matchesWholeNumber = type.contains(.wholeNumber)
		let matchesDecimalNumber = type.contains(.decimalNumber)
		var matchesPositiveNumber = type.contains(.positiveNumber)
		let matchesNegativeNumber = type.contains(.negativeNumber)
		let matchesNumber = matchesWholeNumber || matchesDecimalNumber
		if !matchesPositiveNumber, !matchesNegativeNumber {
			matchesPositiveNumber = true
		}
		let matchesAlphabet = type.contains(.alphabetic)
		var matchedDecimal = false

		for index in 0 ..< length {
			let character = character(at: index)
			if matchesNumber {
				if index == 0 {
					if character == 45, !matchesNegativeNumber {
						return false
					}
					if character != 45, !matchesPositiveNumber {
						return false
					}
				}

				if character == 46 {
					guard matchesDecimalNumber, !matchedDecimal else {
						return false
					}
					matchedDecimal = true
				}
			}

			let isAlphabetic = 65 ... 90 ~= character || 97 ... 122 ~= character
			let isNumeric = 48 ... 57 ~= character
			if isAlphabetic && matchesAlphabet || isNumeric && matchesNumber {
				continue
			}
			return false
		}

		return !(!matchesPositiveNumber && matchesDecimalNumber && !matchedDecimal)
	}

	@objc(containsCharactersFromCharacterSet:)
	func ce_containsCharacters(from characterSet: CharacterSet) -> Bool {
		rangeOfCharacter(from: characterSet).location != NSNotFound
	}

	@objc(onlyContainsCharactersFromCharacterSet:)
	func ce_onlyContainsCharacters(from characterSet: CharacterSet) -> Bool {
		rangeOfCharacter(from: characterSet.inverted).location == NSNotFound
	}

	@objc(containsCharacters:)
	func ce_containsCharacters(_ characters: String) -> Bool {
		ce_containsCharacters(from: CharacterSet(charactersIn: characters))
	}

	@objc(formDataUsingSeparator:)
	func ce_formData(usingSeparator separator: String) -> [String: String] {
		ce_formData(usingSeparator: separator) { value in
			(value as NSString).ce_percentDecodedString ?? value
		}
	}

	@objc(formDataUsingSeparator:decodingBlock:)
	func ce_formData(
		usingSeparator separator: String,
		decodingWith decode: (String) -> String
	) -> [String: String] {
		guard length > 0 else {
			return [:]
		}

		var result: [String: String] = [:]
		for component in components(separatedBy: separator) where !component.isEmpty {
			let componentString = component as NSString
			let equalsPosition = componentString.ce_stringPosition("=")
			if equalsPosition < 0 {
				result[component] = ""
			} else {
				let name = componentString.substring(to: equalsPosition)
				let value = componentString.ce_substring(after: UInt(equalsPosition)) as String
				result[name] = decode(value)
			}
		}
		return result
	}

	@objc(URLQueryItems)
	var ce_URLQueryItems: [String: String] {
		ce_formData(usingSeparator: "&")
	}

	@objc(normalizeSpaces)
	var ce_normalizeSpaces: NSString {
		guard length > 0 else {
			return self
		}

		let removeSet = CharacterSet(charactersIn: "\u{200B}")
		var replaceSet = CharacterSet()
		replaceSet.insert(charactersIn: Unicode.Scalar(0x00A0)! ... Unicode.Scalar(0x00A0)!)
		replaceSet.insert(charactersIn: Unicode.Scalar(0x2002)! ... Unicode.Scalar(0x200A)!)
		replaceSet.insert(charactersIn: Unicode.Scalar(0x202F)! ... Unicode.Scalar(0x202F)!)
		replaceSet.insert(charactersIn: Unicode.Scalar(0x205F)! ... Unicode.Scalar(0x205F)!)
		replaceSet.insert(charactersIn: Unicode.Scalar(0x3000)! ... Unicode.Scalar(0x3000)!)
		replaceSet.insert(charactersIn: Unicode.Scalar(0xE0020)! ... Unicode.Scalar(0xE0020)!)

		let removed = UTF16StringOperations.replacingCharacters(in: self, from: removeSet, with: "")
		return UTF16StringOperations.replacingCharacters(in: removed, from: replaceSet, with: " ")
	}

	@objc(standardizedTildePath)
	var ce_standardizedTildePath: NSString? {
		let homeDirectory = FileManager.pathOfHomeDirectoryOutsideSandbox
		var result = standardizingPath
		guard result.hasPrefix(homeDirectory) else {
			return self
		}

		let homeLength = (homeDirectory as NSString).length
		let resultString = result as NSString
		if homeLength == resultString.length {
			return "~"
		}
		guard resultString.character(at: homeLength) == 47 else {
			return result as NSString
		}

		result = resultString.substring(from: homeLength)
		return ("~" + result) as NSString
	}
}

public extension NSString {
	@objc(percentEncodedStringWithAllowedCharacters:)
	func ce_percentEncodedString(withAllowedCharacters allowedCharacters: String) -> NSString? {
		addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: allowedCharacters)) as NSString?
	}

	@objc(percentDecodedString)
	var ce_percentDecodedString: String? {
		removingPercentEncoding
	}

	@objc(percentEncodedString)
	var ce_percentEncodedString: String? {
		addingPercentEncoding(withAllowedCharacters: NSCharacterSet.textual_percentEncodedCharacterSet as CharacterSet)
	}

	@objc(percentEncodedURLPath)
	var ce_percentEncodedURLPath: String? {
		addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
	}

	@objc(percentEncodedURLQuery)
	var ce_percentEncodedURLQuery: String? {
		addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
	}

	@objc(stringWithUniChar:)
	class func ce_string(with value: unichar) -> NSString {
		var value = value
		return NSString(characters: &value, length: 1)
	}

	@objc(stringWithUnsignedShort:)
	class func ce_string(withUnsignedShort value: UInt16) -> NSString {
		String(value) as NSString
	}

	@objc(stringWithInteger:)
	class func ce_string(with value: Int) -> NSString {
		String(value) as NSString
	}

	@objc(stringWithUnsignedInteger:)
	class func ce_string(withUnsignedInteger value: UInt) -> NSString {
		String(value) as NSString
	}
}

public extension NSAttributedString {
	@objc(attributes)
	var ce_attributes: [NSAttributedString.Key: Any] {
		attributes(at: 0, longestEffectiveRange: nil, in: NSRange(location: 0, length: length))
	}

	@objc(range)
	var ce_range: NSRange {
		NSRange(location: 0, length: length)
	}

	@objc(attributedString)
	class func ce_attributedString() -> NSAttributedString {
		ce_attributedString(with: "")
	}

	@objc(attributedStringWithString:)
	class func ce_attributedString(with string: String) -> NSAttributedString {
		NSAttributedString(string: string)
	}

	@objc(attributedStringWithString:attributes:)
	class func ce_attributedString(
		with string: String,
		attributes: [NSAttributedString.Key: Any]
	) -> NSAttributedString {
		NSAttributedString(string: string, attributes: attributes)
	}

	@objc(attributedSubstringFromIndex:)
	func ce_attributedSubstring(from index: UInt) -> NSAttributedString {
		attributedSubstring(from: NSRange(location: Int(index), length: length - Int(index)))
	}

	@objc(splitIntoLines)
	var ce_splitIntoLines: [NSAttributedString] {
		guard length > 0 else {
			return []
		}

		let sourceString = string as NSString
		var result: [NSAttributedString] = []
		var lineStart = 0
		while lineStart < sourceString.length {
			let searchRange = NSRange(location: lineStart, length: sourceString.length - lineStart)
			let newlineRange = sourceString.rangeOfCharacter(from: .newlines, options: [], range: searchRange)
			guard newlineRange.location != NSNotFound else {
				break
			}

			result.append(attributedSubstring(from: NSRange(
				location: lineStart,
				length: newlineRange.location - lineStart
			)))
			lineStart = NSMaxRange(newlineRange)
		}

		guard !result.isEmpty else {
			return [self]
		}
		if lineStart < sourceString.length {
			result.append(attributedSubstring(from: NSRange(
				location: lineStart,
				length: sourceString.length - lineStart
			)))
		}
		return result
	}

	@objc(isAttributeSet:atIndex:)
	func ce_isAttributeSet(_ attribute: String, at index: UInt) -> Bool {
		ce_isAttributeSet(attribute, at: index, attributeValue: nil)
	}

	@objc(isAttributeSet:atIndex:attributeValue:)
	func ce_isAttributeSet(
		_ attribute: String,
		at index: UInt,
		attributeValue: AutoreleasingUnsafeMutablePointer<AnyObject?>?
	) -> Bool {
		guard let value = self.attribute(NSAttributedString.Key(attribute), at: Int(index), effectiveRange: nil) else {
			return false
		}
		attributeValue?.pointee = value as AnyObject
		return true
	}

	@objc(isAttributeSet:inRange:)
	func ce_isAttributeSet(_ attribute: String, in range: NSRange) -> Bool {
		ce_isAttributeSet(attribute, in: range, attributeValue: nil)
	}

	@objc(isAttributeSet:inRange:attributeValue:)
	func ce_isAttributeSet(
		_ attribute: String,
		in range: NSRange,
		attributeValue: AutoreleasingUnsafeMutablePointer<AnyObject?>?
	) -> Bool {
		ce_isAttributeSet(attribute, at: UInt(range.location), attributeValue: attributeValue)
	}
}

public extension NSMutableAttributedString {
	@objc(mutableAttributedStringWithString:)
	class func ce_mutableAttributedString(with string: String) -> NSMutableAttributedString {
		NSMutableAttributedString(string: string)
	}

	@objc(mutableAttributedStringWithString:attributes:)
	class func ce_mutableAttributedString(
		with string: String,
		attributes: [NSAttributedString.Key: Any]
	) -> NSMutableAttributedString {
		NSMutableAttributedString(string: string, attributes: attributes)
	}

	@objc(trimmedString)
	var ce_trimmedString: String {
		(string as NSString).ce_trim as String
	}

	@objc(appendString:)
	func ce_append(_ string: String) {
		append(NSAttributedString(string: string))
	}

	@objc(appendString:attributes:)
	func ce_append(_ string: String, attributes: [NSAttributedString.Key: Any]) {
		append(NSAttributedString(string: string, attributes: attributes))
	}

	@objc(addAttribute:value:startingAt:)
	func ce_addAttribute(_ attribute: String, value: Any, startingAt index: UInt) {
		ce_addAttributes([NSAttributedString.Key(attribute): value], startingAt: index)
	}

	@objc(addAttributes:startingAt:)
	func ce_addAttributes(_ attributes: [NSAttributedString.Key: Any], startingAt index: UInt) {
		addAttributes(attributes, range: NSRange(location: Int(index), length: length - Int(index)))
	}

	@objc(removeAttribute:startingAt:)
	func ce_removeAttribute(_ attribute: String, startingAt index: UInt) {
		removeAttribute(
			NSAttributedString.Key(attribute),
			range: NSRange(location: Int(index), length: length - Int(index))
		)
	}

	@objc(resetAttributesStaringAt:)
	func ce_resetAttributes(startingAt index: UInt) {
		setAttributes([:], range: NSRange(location: Int(index), length: length - Int(index)))
	}
}
