/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
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

import Foundation

@objc(XRRegularExpression)
public final class RegularExpression: NSObject {
	@objc(string:isMatchedByRegex:)
	public static func string(_ haystack: String, isMatchedByRegex needle: String) -> Bool {
		string(haystack, isMatchedByRegex: needle, withoutCase: false)
	}

	@objc(string:isMatchedByRegex:withoutCase:)
	public static func string(_ haystack: String, isMatchedByRegex needle: String, withoutCase caseless: Bool) -> Bool {
		makeExpression(needle, caseless: caseless)?.firstMatch(in: haystack, range: haystack.fullRange) != nil
	}

	@objc(string:rangeOfRegex:)
	public static func string(_ haystack: String, rangeOfRegex needle: String) -> NSRange {
		string(haystack, rangeOfRegex: needle, withoutCase: false)
	}

	@objc(string:rangeOfRegex:withoutCase:)
	public static func string(_ haystack: String, rangeOfRegex needle: String, withoutCase caseless: Bool) -> NSRange {
		makeExpression(needle, caseless: caseless)?.rangeOfFirstMatch(in: haystack, range: haystack.fullRange)
			?? NSRange(location: NSNotFound, length: 0)
	}

	@objc(string:replacedByRegex:withString:)
	public static func string(_ haystack: String, replacedByRegex needle: String, with replacement: String) -> String {
		makeExpression(needle)?.stringByReplacingMatches(
			in: haystack,
			range: haystack.fullRange,
			withTemplate: replacement
		)
			?? haystack
	}

	@objc(matchesInString:withRegex:withoutCase:substringGroups:)
	public static func matches(
		in haystack: String,
		withRegex needle: String,
		withoutCase caseless: Bool,
		substringGroups: Bool
	) -> [String] {
		guard let expression = makeExpression(needle, caseless: caseless) else { return [] }

		return expression.matches(in: haystack, range: haystack.fullRange).flatMap { result in
			let ranges = substringGroups ? (0 ..< result.numberOfRanges) : (0 ..< 1)
			return ranges.compactMap { index -> String? in
				let range = result.range(at: index)
				guard range.location != NSNotFound, let swiftRange = Range(range, in: haystack) else { return nil }
				return String(haystack[swiftRange])
			}
		}
	}

	@objc(matches:inString:withRegex:)
	public static func matchCount(
		_ matches: AutoreleasingUnsafeMutablePointer<NSArray?>?,
		in haystack: String,
		withRegex needle: String
	) -> UInt {
		matchCount(matches, in: haystack, withRegex: needle, withoutCase: false, substringGroups: false)
	}

	@objc(matches:inString:withRegex:withoutCase:)
	public static func matchCount(
		_ matches: AutoreleasingUnsafeMutablePointer<NSArray?>?,
		in haystack: String,
		withRegex needle: String,
		withoutCase caseless: Bool
	) -> UInt {
		matchCount(matches, in: haystack, withRegex: needle, withoutCase: caseless, substringGroups: false)
	}

	@objc(matches:inString:withRegex:withoutCase:substringGroups:)
	public static func matchCount(
		_ matches: AutoreleasingUnsafeMutablePointer<NSArray?>?,
		in haystack: String,
		withRegex needle: String,
		withoutCase caseless: Bool,
		substringGroups: Bool
	) -> UInt {
		let result = self.matches(
			in: haystack,
			withRegex: needle,
			withoutCase: caseless,
			substringGroups: substringGroups
		)
		matches?.pointee = result as NSArray
		return UInt(result.count)
	}

	private static func makeExpression(_ pattern: String, caseless: Bool = false) -> NSRegularExpression? {
		try? NSRegularExpression(pattern: pattern, options: caseless ? .caseInsensitive : [])
	}
}

private extension String {
	var fullRange: NSRange {
		NSRange(startIndex ..< endIndex, in: self)
	}
}
