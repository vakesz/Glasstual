/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
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
 *
 *********************************************************************** */

import Foundation

/// The preferences the inline-content service reads.
///
/// The app used to warm the service by handing it its entire registered
/// defaults domain as `[String: Any]`: every preference the app has, untyped,
/// crossing a process boundary with no class allowlist, so that the service
/// could read eight values. This carries those eight and nothing else.
@objc(ICLInlineContentServicePreferences)
public final nonisolated class InlineContentServicePreferences: NSObject, NSSecureCoding, Sendable {
	@objc public let maximumFilesize: UInt
	@objc public let scalingWidth: UInt
	@objc public let maximumHeight: UInt
	@objc public let limitToBasics: Bool
	@objc public let limitBasicsToFiles: Bool
	@objc public let limitNaughtyContent: Bool
	@objc public let limitUnsafeContent: Bool
	@objc public let checkEverything: Bool
	@objc public let allowsCleartextHTTP: Bool

	public init(
		maximumFilesize: UInt,
		scalingWidth: UInt,
		maximumHeight: UInt,
		limitToBasics: Bool,
		limitBasicsToFiles: Bool,
		limitNaughtyContent: Bool,
		limitUnsafeContent: Bool,
		checkEverything: Bool,
		allowsCleartextHTTP: Bool
	) {
		self.maximumFilesize = maximumFilesize
		self.scalingWidth = scalingWidth
		self.maximumHeight = maximumHeight
		self.limitToBasics = limitToBasics
		self.limitBasicsToFiles = limitBasicsToFiles
		self.limitNaughtyContent = limitNaughtyContent
		self.limitUnsafeContent = limitUnsafeContent
		self.checkEverything = checkEverything
		self.allowsCleartextHTTP = allowsCleartextHTTP

		super.init()
	}

	/// The values the app currently holds, read through a private handle: the
	/// client that pushes them to the service is an actor of its own.
	@objc public static func current() -> InlineContentServicePreferences {
		InlineContentServicePreferences(
			maximumFilesize: Preferences.InlineMedia.maximumFilesize.detachedValue,
			scalingWidth: Preferences.InlineMedia.scalingWidth.detachedValue,
			maximumHeight: Preferences.InlineMedia.maximumHeight.detachedValue,
			limitToBasics: Preferences.InlineMedia.limitToBasics.detachedValue,
			limitBasicsToFiles: Preferences.InlineMedia.limitBasicsToFiles.detachedValue,
			limitNaughtyContent: Preferences.InlineMedia.limitNaughtyContent.detachedValue,
			limitUnsafeContent: Preferences.InlineMedia.limitUnsafeContent.detachedValue,
			checkEverything: Preferences.InlineMedia.checkEverything.detachedValue,
			allowsCleartextHTTP: Preferences.InlineMedia.allowsCleartextHTTP.detachedValue
		)
	}

	/// The same values as a defaults registration domain, so that the service's
	/// `TextualPreferences` accessors read them through their usual keys.
	@objc public var registrationDomain: [String: Any] {
		[
			Preferences.InlineMedia.maximumFilesize.name: maximumFilesize,
			Preferences.InlineMedia.scalingWidth.name: scalingWidth,
			Preferences.InlineMedia.maximumHeight.name: maximumHeight,
			Preferences.InlineMedia.limitToBasics.name: limitToBasics,
			Preferences.InlineMedia.limitBasicsToFiles.name: limitBasicsToFiles,
			Preferences.InlineMedia.limitNaughtyContent.name: limitNaughtyContent,
			Preferences.InlineMedia.limitUnsafeContent.name: limitUnsafeContent,
			Preferences.InlineMedia.checkEverything.name: checkEverything,
			Preferences.InlineMedia.allowsCleartextHTTP.name: allowsCleartextHTTP,
		]
	}

	// MARK: - NSSecureCoding

	public static var supportsSecureCoding: Bool {
		true
	}

	private enum CodingKey {
		static let maximumFilesize = "maximumFilesize"
		static let scalingWidth = "scalingWidth"
		static let maximumHeight = "maximumHeight"
		static let limitToBasics = "limitToBasics"
		static let limitBasicsToFiles = "limitBasicsToFiles"
		static let limitNaughtyContent = "limitNaughtyContent"
		static let limitUnsafeContent = "limitUnsafeContent"
		static let checkEverything = "checkEverything"
		static let allowsCleartextHTTP = "allowsCleartextHTTP"
	}

	public init?(coder: NSCoder) {
		maximumFilesize = UInt(max(coder.decodeInteger(forKey: CodingKey.maximumFilesize), 0))
		scalingWidth = UInt(max(coder.decodeInteger(forKey: CodingKey.scalingWidth), 0))
		maximumHeight = UInt(max(coder.decodeInteger(forKey: CodingKey.maximumHeight), 0))
		limitToBasics = coder.decodeBool(forKey: CodingKey.limitToBasics)
		limitBasicsToFiles = coder.decodeBool(forKey: CodingKey.limitBasicsToFiles)
		limitNaughtyContent = coder.decodeBool(forKey: CodingKey.limitNaughtyContent)
		limitUnsafeContent = coder.decodeBool(forKey: CodingKey.limitUnsafeContent)
		checkEverything = coder.decodeBool(forKey: CodingKey.checkEverything)
		/* Absent from an older archive, where the gate did not exist and
		 cleartext was always allowed. */
		allowsCleartextHTTP = coder.containsValue(forKey: CodingKey.allowsCleartextHTTP)
			? coder.decodeBool(forKey: CodingKey.allowsCleartextHTTP)
			: true

		super.init()
	}

	public func encode(with coder: NSCoder) {
		coder.encode(Int(maximumFilesize), forKey: CodingKey.maximumFilesize)
		coder.encode(Int(scalingWidth), forKey: CodingKey.scalingWidth)
		coder.encode(Int(maximumHeight), forKey: CodingKey.maximumHeight)
		coder.encode(limitToBasics, forKey: CodingKey.limitToBasics)
		coder.encode(limitBasicsToFiles, forKey: CodingKey.limitBasicsToFiles)
		coder.encode(limitNaughtyContent, forKey: CodingKey.limitNaughtyContent)
		coder.encode(limitUnsafeContent, forKey: CodingKey.limitUnsafeContent)
		coder.encode(checkEverything, forKey: CodingKey.checkEverything)
		coder.encode(allowsCleartextHTTP, forKey: CodingKey.allowsCleartextHTTP)
	}
}
