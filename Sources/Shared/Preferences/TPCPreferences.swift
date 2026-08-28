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

public extension TextualPreferences {
	class func inlineImagesMaxFilesize() -> UInt64 {
		let megabytesByPreference: [UInt: UInt64] = [
			1: 1, 2: 2, 3: 3, 4: 4, 5: 5,
			6: 10, 7: 15, 8: 20, 9: 50, 10: 100,
		]
		let preference = TextualUserDefaults.shared().integer(forKey: "InlineMediaMaximumFilesize")
		return (megabytesByPreference[UInt(preference)] ?? 2) * 1_048_576
	}

	class func inlineMediaMaxWidth() -> UInt {
		UInt(TextualUserDefaults.shared().integer(forKey: "InlineMediaScalingWidth"))
	}

	class func inlineMediaMaxHeight() -> UInt {
		UInt(TextualUserDefaults.shared().integer(forKey: "InlineMediaMaximumHeight"))
	}

	class func setInlineMediaMaxWidth(_ value: UInt) {
		TextualUserDefaults.shared().set(Int(value), forKey: "InlineMediaScalingWidth")
	}

	class func setInlineMediaMaxHeight(_ value: UInt) {
		TextualUserDefaults.shared().set(Int(value), forKey: "InlineMediaMaximumHeight")
	}

	class func inlineMediaLimitToBasics() -> Bool {
		TextualUserDefaults.shared().bool(forKey: "InlineMediaLimitToBasics")
	}

	class func setInlineMediaLimitToBasics(_ value: Bool) {
		TextualUserDefaults.shared().set(value, forKey: "InlineMediaLimitToBasics")
	}

	class func inlineMediaLimitBasicsToFiles() -> Bool {
		TextualUserDefaults.shared().bool(forKey: "InlineMediaLimitBasicsToFiles")
	}

	class func setInlineMediaLimitBasicsToFiles(_ value: Bool) {
		TextualUserDefaults.shared().set(value, forKey: "InlineMediaLimitBasicsToFiles")
	}

	class func inlineMediaLimitNaughtyContent() -> Bool {
		TextualUserDefaults.shared().bool(forKey: "InlineMediaLimitNaughtyContent")
	}

	class func inlineMediaLimitUnsafeContent() -> Bool {
		TextualUserDefaults.shared().bool(forKey: "InlineMediaLimitUnsafeContent")
	}

	class func inlineMediaCheckEverything() -> Bool {
		TextualUserDefaults.shared().bool(forKey: "InlineMediaCheckEverything")
	}
}
