/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

@objc(TPCPreferences)
public class TextualPreferences: NSObject {}

public nonisolated extension Preferences {
	/** Inline media: what is fetched, how large it may be, and how far it is
	 scaled.

	 Declared beside the shared defaults class rather than with the rest of the
	 catalogue because the inline-content XPC service compiles this file and
	 reads the same declarations, instead of keeping a second copy of the key
	 names. */
	nonisolated enum InlineMedia {
		public static let maximumFilesize = PreferenceKey("InlineMediaMaximumFilesize", default: UInt(2))
		public static let scalingWidth = PreferenceKey("InlineMediaScalingWidth", default: UInt(300))
		public static let maximumHeight = PreferenceKey("InlineMediaMaximumHeight", default: UInt(0))
		public static let limitToBasics = PreferenceKey("InlineMediaLimitToBasics", default: false)
		public static let limitBasicsToFiles = PreferenceKey("InlineMediaLimitBasicsToFiles", default: false)
		public static let limitNaughtyContent = PreferenceKey("InlineMediaLimitNaughtyContent", default: true)
		public static let limitUnsafeContent = PreferenceKey("InlineMediaLimitUnsafeContent", default: true)
		public static let checkEverything = PreferenceKey("InlineMediaCheckEverything", default: false)

		/** Whether inline media may be fetched from a cleartext `http` URL.

		 The app's Info.plist keeps `NSAllowsArbitraryLoadsInWebContent` on so
		 that the channel log can render the http-only images and video that
		 make up a good share of what gets posted to IRC. That switch is
		 all-or-nothing and cannot be changed at runtime, so this preference is
		 the gate: the inline-content service refuses an http URL when it is
		 off, and the log view never sees one. On by default, so nothing that
		 worked before stops working. */
		public static let allowsCleartextHTTP = PreferenceKey("InlineMediaAllowsCleartextHTTP", default: true)

		public static let all: [any AnyPreferenceKey] = [
			maximumFilesize, scalingWidth, maximumHeight, limitToBasics, limitBasicsToFiles,
			limitNaughtyContent, limitUnsafeContent, checkEverything, allowsCleartextHTTP,
		]
	}
}

public extension TextualPreferences {
	class func inlineImagesMaxFilesize() -> UInt64 {
		let megabytesByPreference: [UInt: UInt64] = [
			1: 1, 2: 2, 3: 3, 4: 4, 5: 5,
			6: 10, 7: 15, 8: 20, 9: 50, 10: 100,
		]

		return (megabytesByPreference[Preferences.InlineMedia.maximumFilesize.value] ?? 2) * 1_048_576
	}

	class func inlineMediaMaxWidth() -> UInt {
		Preferences.InlineMedia.scalingWidth.value
	}

	class func inlineMediaMaxHeight() -> UInt {
		Preferences.InlineMedia.maximumHeight.value
	}

	class func setInlineMediaMaxWidth(_ value: UInt) {
		Preferences.InlineMedia.scalingWidth.value = value
	}

	class func setInlineMediaMaxHeight(_ value: UInt) {
		Preferences.InlineMedia.maximumHeight.value = value
	}

	class func inlineMediaLimitToBasics() -> Bool {
		Preferences.InlineMedia.limitToBasics.value
	}

	class func setInlineMediaLimitToBasics(_ value: Bool) {
		Preferences.InlineMedia.limitToBasics.value = value
	}

	class func inlineMediaLimitBasicsToFiles() -> Bool {
		Preferences.InlineMedia.limitBasicsToFiles.value
	}

	class func setInlineMediaLimitBasicsToFiles(_ value: Bool) {
		Preferences.InlineMedia.limitBasicsToFiles.value = value
	}

	class func inlineMediaLimitNaughtyContent() -> Bool {
		Preferences.InlineMedia.limitNaughtyContent.value
	}

	class func inlineMediaLimitUnsafeContent() -> Bool {
		Preferences.InlineMedia.limitUnsafeContent.value
	}

	class func inlineMediaCheckEverything() -> Bool {
		Preferences.InlineMedia.checkEverything.value
	}

	class func inlineMediaAllowsCleartextHTTP() -> Bool {
		Preferences.InlineMedia.allowsCleartextHTTP.value
	}

	/// Whether inline media may be loaded from `url`.
	///
	/// Only `http` and `https` are ever inlined; `http` additionally depends on
	/// ``Preferences/InlineMedia/allowsCleartextHTTP``.
	class func permitsInlineMedia(at url: URL) -> Bool {
		switch url.scheme?.lowercased() {
		case "https": true
		case "http": Preferences.InlineMedia.allowsCleartextHTTP.value
		default: false
		}
	}
}
