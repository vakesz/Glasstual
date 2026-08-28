/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2006 - 2008 Google Inc.
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Licensed under the Apache License, Version 2.0
 *
 *********************************************************************** */

import Foundation

private struct HTMLEscapeMap {
	let sequence: String
	let code: UInt16
}

nonisolated extension NSString {
	@objc(gtm_stringByEscapingForHTML)
	public var gtmStringByEscapingForHTML: String? {
		stringByEscapingHTML(using: Self.unicodeHTMLEscapeMap, escapeUnicode: false)
	}

	@objc(gtm_stringByEscapingForAsciiHTML)
	public var gtmStringByEscapingForAsciiHTML: String {
		stringByEscapingHTML(using: Self.asciiHTMLEscapeMap, escapeUnicode: true) ?? (self as String)
	}

	@objc(gtm_stringByUnescapingFromHTML)
	public var gtmStringByUnescapingFromHTML: String {
		var range = NSRange(location: 0, length: length)
		var subrange = self.range(of: "&", options: .backwards, range: range)

		guard subrange.length != 0 else {
			return self as String
		}

		let finalString = NSMutableString(string: self as String)

		repeat {
			var semiColonRange = NSRange(location: subrange.location, length: NSMaxRange(range) - subrange.location)
			semiColonRange = self.range(of: ";", options: [], range: semiColonRange)
			range = NSRange(location: 0, length: subrange.location)

			if semiColonRange.location == NSNotFound {
				continue
			}

			let escapeRange = NSRange(
				location: subrange.location,
				length: semiColonRange.location - subrange.location + 1
			)
			let escapeString = substring(with: escapeRange) as NSString
			let escapeLength = escapeString.length

			if escapeLength > 3, escapeLength < 11 {
				if escapeString.character(at: 1) == 0x23 { // '#'
					let char2 = escapeString.character(at: 2)

					if char2 == 0x78 || char2 == 0x58 { // 'x' or 'X'
						let hexSequence = escapeString.substring(with: NSRange(location: 3, length: escapeLength - 4))
						if let value = UInt32(hexSequence, radix: 16), value > 0 {
							if value < UInt32(UInt16.max) {
								finalString.replaceCharacters(
									in: escapeRange,
									with: Self.string(fromUTF16: [UniChar(value)])
								)
							} else if value >= 0x10000, value <= 0x10FFFF {
								let subtractedValue = Int(value - 0x10000)
								let uchars: [UniChar] = [
									UniChar(0xD800 + (subtractedValue >> 10)),
									UniChar(0xDC00 + (subtractedValue & 0x3FF)),
								]
								finalString.replaceCharacters(in: escapeRange, with: Self.string(fromUTF16: uchars))
							}
						}
					} else {
						let numberSequence = escapeString.substring(with: NSRange(
							location: 2,
							length: escapeLength - 3
						))
						if let value = Int(numberSequence), value > 0 {
							if value < Int(UInt16.max) {
								finalString.replaceCharacters(
									in: escapeRange,
									with: Self.string(fromUTF16: [UniChar(value)])
								)
							} else if value >= 0x10000, value <= 0x10FFFF {
								let subtractedValue = value - 0x10000
								let uchars: [UniChar] = [
									UniChar(0xD800 + (subtractedValue >> 10)),
									UniChar(0xDC00 + (subtractedValue & 0x3FF)),
								]
								finalString.replaceCharacters(in: escapeRange, with: Self.string(fromUTF16: uchars))
							}
						}
					}
				} else {
					for entry in Self.asciiHTMLEscapeMap where escapeString as String == entry.sequence {
						finalString.replaceCharacters(in: escapeRange, with: Self.string(fromUTF16: [entry.code]))
						break
					}
				}
			}
		} while ({
			subrange = self.range(of: "&", options: .backwards, range: range)
			return subrange.length != 0
		}())

		return finalString as String
	}

	private func stringByEscapingHTML(using table: [HTMLEscapeMap], escapeUnicode: Bool) -> String? {
		let length = length

		if length == 0 {
			return self as String
		}

		let finalString = NSMutableString()
		var buffer2: [UniChar] = []
		buffer2.reserveCapacity(length)

		for i in 0 ..< length {
			let character = character(at: i)

			if let match = Self.escapeMapEntry(for: character, in: table) {
				if buffer2.isEmpty == false {
					finalString.append(Self.string(fromUTF16: buffer2))
					buffer2.removeAll(keepingCapacity: true)
				}

				finalString.append(match.sequence)
			} else if escapeUnicode, character > 127 {
				if buffer2.isEmpty == false {
					finalString.append(Self.string(fromUTF16: buffer2))
					buffer2.removeAll(keepingCapacity: true)
				}

				finalString.appendFormat("&#%d;", character)
			} else {
				buffer2.append(character)
			}
		}

		if buffer2.isEmpty == false {
			finalString.append(Self.string(fromUTF16: buffer2))
		}

		return finalString as String
	}

	private static func string(fromUTF16 codeUnits: [UniChar]) -> String {
		codeUnits.withUnsafeBufferPointer { buffer in
			String(utf16CodeUnits: buffer.baseAddress!, count: buffer.count)
		}
	}

	private static func escapeMapEntry(for character: UniChar, in table: [HTMLEscapeMap]) -> HTMLEscapeMap? {
		var low = 0
		var high = table.count - 1

		while low <= high {
			let mid = (low + high) / 2
			let midCode = table[mid].code

			if character > midCode {
				low = mid + 1
			} else if character < midCode {
				high = mid - 1
			} else {
				return table[mid]
			}
		}

		return nil
	}

	private static let unicodeHTMLEscapeMap: [HTMLEscapeMap] = [
		HTMLEscapeMap(sequence: "&quot;", code: 34),
		HTMLEscapeMap(sequence: "&amp;", code: 38),
		HTMLEscapeMap(sequence: "&apos;", code: 39),
		HTMLEscapeMap(sequence: "&lt;", code: 60),
		HTMLEscapeMap(sequence: "&gt;", code: 62),
		HTMLEscapeMap(sequence: "&OElig;", code: 338),
		HTMLEscapeMap(sequence: "&oelig;", code: 339),
		HTMLEscapeMap(sequence: "&Scaron;", code: 352),
		HTMLEscapeMap(sequence: "&scaron;", code: 353),
		HTMLEscapeMap(sequence: "&Yuml;", code: 376),
		HTMLEscapeMap(sequence: "&circ;", code: 710),
		HTMLEscapeMap(sequence: "&tilde;", code: 732),
		HTMLEscapeMap(sequence: "&ensp;", code: 8194),
		HTMLEscapeMap(sequence: "&emsp;", code: 8195),
		HTMLEscapeMap(sequence: "&thinsp;", code: 8201),
		HTMLEscapeMap(sequence: "&zwnj;", code: 8204),
		HTMLEscapeMap(sequence: "&zwj;", code: 8205),
		HTMLEscapeMap(sequence: "&lrm;", code: 8206),
		HTMLEscapeMap(sequence: "&rlm;", code: 8207),
		HTMLEscapeMap(sequence: "&ndash;", code: 8211),
		HTMLEscapeMap(sequence: "&mdash;", code: 8212),
		HTMLEscapeMap(sequence: "&lsquo;", code: 8216),
		HTMLEscapeMap(sequence: "&rsquo;", code: 8217),
		HTMLEscapeMap(sequence: "&sbquo;", code: 8218),
		HTMLEscapeMap(sequence: "&ldquo;", code: 8220),
		HTMLEscapeMap(sequence: "&rdquo;", code: 8221),
		HTMLEscapeMap(sequence: "&bdquo;", code: 8222),
		HTMLEscapeMap(sequence: "&dagger;", code: 8224),
		HTMLEscapeMap(sequence: "&Dagger;", code: 8225),
		HTMLEscapeMap(sequence: "&permil;", code: 8240),
		HTMLEscapeMap(sequence: "&lsaquo;", code: 8249),
		HTMLEscapeMap(sequence: "&rsaquo;", code: 8250),
		HTMLEscapeMap(sequence: "&euro;", code: 8364),
	]

	private static let asciiHTMLEscapeMap: [HTMLEscapeMap] = [
		HTMLEscapeMap(sequence: "&quot;", code: 34),
		HTMLEscapeMap(sequence: "&amp;", code: 38),
		HTMLEscapeMap(sequence: "&apos;", code: 39),
		HTMLEscapeMap(sequence: "&lt;", code: 60),
		HTMLEscapeMap(sequence: "&gt;", code: 62),
		HTMLEscapeMap(sequence: "&nbsp;", code: 160),
		HTMLEscapeMap(sequence: "&iexcl;", code: 161),
		HTMLEscapeMap(sequence: "&cent;", code: 162),
		HTMLEscapeMap(sequence: "&pound;", code: 163),
		HTMLEscapeMap(sequence: "&curren;", code: 164),
		HTMLEscapeMap(sequence: "&yen;", code: 165),
		HTMLEscapeMap(sequence: "&brvbar;", code: 166),
		HTMLEscapeMap(sequence: "&sect;", code: 167),
		HTMLEscapeMap(sequence: "&uml;", code: 168),
		HTMLEscapeMap(sequence: "&copy;", code: 169),
		HTMLEscapeMap(sequence: "&ordf;", code: 170),
		HTMLEscapeMap(sequence: "&laquo;", code: 171),
		HTMLEscapeMap(sequence: "&not;", code: 172),
		HTMLEscapeMap(sequence: "&shy;", code: 173),
		HTMLEscapeMap(sequence: "&reg;", code: 174),
		HTMLEscapeMap(sequence: "&macr;", code: 175),
		HTMLEscapeMap(sequence: "&deg;", code: 176),
		HTMLEscapeMap(sequence: "&plusmn;", code: 177),
		HTMLEscapeMap(sequence: "&sup2;", code: 178),
		HTMLEscapeMap(sequence: "&sup3;", code: 179),
		HTMLEscapeMap(sequence: "&acute;", code: 180),
		HTMLEscapeMap(sequence: "&micro;", code: 181),
		HTMLEscapeMap(sequence: "&para;", code: 182),
		HTMLEscapeMap(sequence: "&middot;", code: 183),
		HTMLEscapeMap(sequence: "&cedil;", code: 184),
		HTMLEscapeMap(sequence: "&sup1;", code: 185),
		HTMLEscapeMap(sequence: "&ordm;", code: 186),
		HTMLEscapeMap(sequence: "&raquo;", code: 187),
		HTMLEscapeMap(sequence: "&frac14;", code: 188),
		HTMLEscapeMap(sequence: "&frac12;", code: 189),
		HTMLEscapeMap(sequence: "&frac34;", code: 190),
		HTMLEscapeMap(sequence: "&iquest;", code: 191),
		HTMLEscapeMap(sequence: "&Agrave;", code: 192),
		HTMLEscapeMap(sequence: "&Aacute;", code: 193),
		HTMLEscapeMap(sequence: "&Acirc;", code: 194),
		HTMLEscapeMap(sequence: "&Atilde;", code: 195),
		HTMLEscapeMap(sequence: "&Auml;", code: 196),
		HTMLEscapeMap(sequence: "&Aring;", code: 197),
		HTMLEscapeMap(sequence: "&AElig;", code: 198),
		HTMLEscapeMap(sequence: "&Ccedil;", code: 199),
		HTMLEscapeMap(sequence: "&Egrave;", code: 200),
		HTMLEscapeMap(sequence: "&Eacute;", code: 201),
		HTMLEscapeMap(sequence: "&Ecirc;", code: 202),
		HTMLEscapeMap(sequence: "&Euml;", code: 203),
		HTMLEscapeMap(sequence: "&Igrave;", code: 204),
		HTMLEscapeMap(sequence: "&Iacute;", code: 205),
		HTMLEscapeMap(sequence: "&Icirc;", code: 206),
		HTMLEscapeMap(sequence: "&Iuml;", code: 207),
		HTMLEscapeMap(sequence: "&ETH;", code: 208),
		HTMLEscapeMap(sequence: "&Ntilde;", code: 209),
		HTMLEscapeMap(sequence: "&Ograve;", code: 210),
		HTMLEscapeMap(sequence: "&Oacute;", code: 211),
		HTMLEscapeMap(sequence: "&Ocirc;", code: 212),
		HTMLEscapeMap(sequence: "&Otilde;", code: 213),
		HTMLEscapeMap(sequence: "&Ouml;", code: 214),
		HTMLEscapeMap(sequence: "&times;", code: 215),
		HTMLEscapeMap(sequence: "&Oslash;", code: 216),
		HTMLEscapeMap(sequence: "&Ugrave;", code: 217),
		HTMLEscapeMap(sequence: "&Uacute;", code: 218),
		HTMLEscapeMap(sequence: "&Ucirc;", code: 219),
		HTMLEscapeMap(sequence: "&Uuml;", code: 220),
		HTMLEscapeMap(sequence: "&Yacute;", code: 221),
		HTMLEscapeMap(sequence: "&THORN;", code: 222),
		HTMLEscapeMap(sequence: "&szlig;", code: 223),
		HTMLEscapeMap(sequence: "&agrave;", code: 224),
		HTMLEscapeMap(sequence: "&aacute;", code: 225),
		HTMLEscapeMap(sequence: "&acirc;", code: 226),
		HTMLEscapeMap(sequence: "&atilde;", code: 227),
		HTMLEscapeMap(sequence: "&auml;", code: 228),
		HTMLEscapeMap(sequence: "&aring;", code: 229),
		HTMLEscapeMap(sequence: "&aelig;", code: 230),
		HTMLEscapeMap(sequence: "&ccedil;", code: 231),
		HTMLEscapeMap(sequence: "&egrave;", code: 232),
		HTMLEscapeMap(sequence: "&eacute;", code: 233),
		HTMLEscapeMap(sequence: "&ecirc;", code: 234),
		HTMLEscapeMap(sequence: "&euml;", code: 235),
		HTMLEscapeMap(sequence: "&igrave;", code: 236),
		HTMLEscapeMap(sequence: "&iacute;", code: 237),
		HTMLEscapeMap(sequence: "&icirc;", code: 238),
		HTMLEscapeMap(sequence: "&iuml;", code: 239),
		HTMLEscapeMap(sequence: "&eth;", code: 240),
		HTMLEscapeMap(sequence: "&ntilde;", code: 241),
		HTMLEscapeMap(sequence: "&ograve;", code: 242),
		HTMLEscapeMap(sequence: "&oacute;", code: 243),
		HTMLEscapeMap(sequence: "&ocirc;", code: 244),
		HTMLEscapeMap(sequence: "&otilde;", code: 245),
		HTMLEscapeMap(sequence: "&ouml;", code: 246),
		HTMLEscapeMap(sequence: "&divide;", code: 247),
		HTMLEscapeMap(sequence: "&oslash;", code: 248),
		HTMLEscapeMap(sequence: "&ugrave;", code: 249),
		HTMLEscapeMap(sequence: "&uacute;", code: 250),
		HTMLEscapeMap(sequence: "&ucirc;", code: 251),
		HTMLEscapeMap(sequence: "&uuml;", code: 252),
		HTMLEscapeMap(sequence: "&yacute;", code: 253),
		HTMLEscapeMap(sequence: "&thorn;", code: 254),
		HTMLEscapeMap(sequence: "&yuml;", code: 255),
		HTMLEscapeMap(sequence: "&OElig;", code: 338),
		HTMLEscapeMap(sequence: "&oelig;", code: 339),
		HTMLEscapeMap(sequence: "&Scaron;", code: 352),
		HTMLEscapeMap(sequence: "&scaron;", code: 353),
		HTMLEscapeMap(sequence: "&Yuml;", code: 376),
		HTMLEscapeMap(sequence: "&fnof;", code: 402),
		HTMLEscapeMap(sequence: "&circ;", code: 710),
		HTMLEscapeMap(sequence: "&tilde;", code: 732),
		HTMLEscapeMap(sequence: "&Alpha;", code: 913),
		HTMLEscapeMap(sequence: "&Beta;", code: 914),
		HTMLEscapeMap(sequence: "&Gamma;", code: 915),
		HTMLEscapeMap(sequence: "&Delta;", code: 916),
		HTMLEscapeMap(sequence: "&Epsilon;", code: 917),
		HTMLEscapeMap(sequence: "&Zeta;", code: 918),
		HTMLEscapeMap(sequence: "&Eta;", code: 919),
		HTMLEscapeMap(sequence: "&Theta;", code: 920),
		HTMLEscapeMap(sequence: "&Iota;", code: 921),
		HTMLEscapeMap(sequence: "&Kappa;", code: 922),
		HTMLEscapeMap(sequence: "&Lambda;", code: 923),
		HTMLEscapeMap(sequence: "&Mu;", code: 924),
		HTMLEscapeMap(sequence: "&Nu;", code: 925),
		HTMLEscapeMap(sequence: "&Xi;", code: 926),
		HTMLEscapeMap(sequence: "&Omicron;", code: 927),
		HTMLEscapeMap(sequence: "&Pi;", code: 928),
		HTMLEscapeMap(sequence: "&Rho;", code: 929),
		HTMLEscapeMap(sequence: "&Sigma;", code: 931),
		HTMLEscapeMap(sequence: "&Tau;", code: 932),
		HTMLEscapeMap(sequence: "&Upsilon;", code: 933),
		HTMLEscapeMap(sequence: "&Phi;", code: 934),
		HTMLEscapeMap(sequence: "&Chi;", code: 935),
		HTMLEscapeMap(sequence: "&Psi;", code: 936),
		HTMLEscapeMap(sequence: "&Omega;", code: 937),
		HTMLEscapeMap(sequence: "&alpha;", code: 945),
		HTMLEscapeMap(sequence: "&beta;", code: 946),
		HTMLEscapeMap(sequence: "&gamma;", code: 947),
		HTMLEscapeMap(sequence: "&delta;", code: 948),
		HTMLEscapeMap(sequence: "&epsilon;", code: 949),
		HTMLEscapeMap(sequence: "&zeta;", code: 950),
		HTMLEscapeMap(sequence: "&eta;", code: 951),
		HTMLEscapeMap(sequence: "&theta;", code: 952),
		HTMLEscapeMap(sequence: "&iota;", code: 953),
		HTMLEscapeMap(sequence: "&kappa;", code: 954),
		HTMLEscapeMap(sequence: "&lambda;", code: 955),
		HTMLEscapeMap(sequence: "&mu;", code: 956),
		HTMLEscapeMap(sequence: "&nu;", code: 957),
		HTMLEscapeMap(sequence: "&xi;", code: 958),
		HTMLEscapeMap(sequence: "&omicron;", code: 959),
		HTMLEscapeMap(sequence: "&pi;", code: 960),
		HTMLEscapeMap(sequence: "&rho;", code: 961),
		HTMLEscapeMap(sequence: "&sigmaf;", code: 962),
		HTMLEscapeMap(sequence: "&sigma;", code: 963),
		HTMLEscapeMap(sequence: "&tau;", code: 964),
		HTMLEscapeMap(sequence: "&upsilon;", code: 965),
		HTMLEscapeMap(sequence: "&phi;", code: 966),
		HTMLEscapeMap(sequence: "&chi;", code: 967),
		HTMLEscapeMap(sequence: "&psi;", code: 968),
		HTMLEscapeMap(sequence: "&omega;", code: 969),
		HTMLEscapeMap(sequence: "&thetasym;", code: 977),
		HTMLEscapeMap(sequence: "&upsih;", code: 978),
		HTMLEscapeMap(sequence: "&piv;", code: 982),
		HTMLEscapeMap(sequence: "&ensp;", code: 8194),
		HTMLEscapeMap(sequence: "&emsp;", code: 8195),
		HTMLEscapeMap(sequence: "&thinsp;", code: 8201),
		HTMLEscapeMap(sequence: "&zwnj;", code: 8204),
		HTMLEscapeMap(sequence: "&zwj;", code: 8205),
		HTMLEscapeMap(sequence: "&lrm;", code: 8206),
		HTMLEscapeMap(sequence: "&rlm;", code: 8207),
		HTMLEscapeMap(sequence: "&ndash;", code: 8211),
		HTMLEscapeMap(sequence: "&mdash;", code: 8212),
		HTMLEscapeMap(sequence: "&lsquo;", code: 8216),
		HTMLEscapeMap(sequence: "&rsquo;", code: 8217),
		HTMLEscapeMap(sequence: "&sbquo;", code: 8218),
		HTMLEscapeMap(sequence: "&ldquo;", code: 8220),
		HTMLEscapeMap(sequence: "&rdquo;", code: 8221),
		HTMLEscapeMap(sequence: "&bdquo;", code: 8222),
		HTMLEscapeMap(sequence: "&dagger;", code: 8224),
		HTMLEscapeMap(sequence: "&Dagger;", code: 8225),
		HTMLEscapeMap(sequence: "&bull;", code: 8226),
		HTMLEscapeMap(sequence: "&hellip;", code: 8230),
		HTMLEscapeMap(sequence: "&permil;", code: 8240),
		HTMLEscapeMap(sequence: "&prime;", code: 8242),
		HTMLEscapeMap(sequence: "&Prime;", code: 8243),
		HTMLEscapeMap(sequence: "&lsaquo;", code: 8249),
		HTMLEscapeMap(sequence: "&rsaquo;", code: 8250),
		HTMLEscapeMap(sequence: "&oline;", code: 8254),
		HTMLEscapeMap(sequence: "&frasl;", code: 8260),
		HTMLEscapeMap(sequence: "&euro;", code: 8364),
		HTMLEscapeMap(sequence: "&image;", code: 8465),
		HTMLEscapeMap(sequence: "&weierp;", code: 8472),
		HTMLEscapeMap(sequence: "&real;", code: 8476),
		HTMLEscapeMap(sequence: "&trade;", code: 8482),
		HTMLEscapeMap(sequence: "&alefsym;", code: 8501),
		HTMLEscapeMap(sequence: "&larr;", code: 8592),
		HTMLEscapeMap(sequence: "&uarr;", code: 8593),
		HTMLEscapeMap(sequence: "&rarr;", code: 8594),
		HTMLEscapeMap(sequence: "&darr;", code: 8595),
		HTMLEscapeMap(sequence: "&harr;", code: 8596),
		HTMLEscapeMap(sequence: "&crarr;", code: 8629),
		HTMLEscapeMap(sequence: "&lArr;", code: 8656),
		HTMLEscapeMap(sequence: "&uArr;", code: 8657),
		HTMLEscapeMap(sequence: "&rArr;", code: 8658),
		HTMLEscapeMap(sequence: "&dArr;", code: 8659),
		HTMLEscapeMap(sequence: "&hArr;", code: 8660),
		HTMLEscapeMap(sequence: "&forall;", code: 8704),
		HTMLEscapeMap(sequence: "&part;", code: 8706),
		HTMLEscapeMap(sequence: "&exist;", code: 8707),
		HTMLEscapeMap(sequence: "&empty;", code: 8709),
		HTMLEscapeMap(sequence: "&nabla;", code: 8711),
		HTMLEscapeMap(sequence: "&isin;", code: 8712),
		HTMLEscapeMap(sequence: "&notin;", code: 8713),
		HTMLEscapeMap(sequence: "&ni;", code: 8715),
		HTMLEscapeMap(sequence: "&prod;", code: 8719),
		HTMLEscapeMap(sequence: "&sum;", code: 8721),
		HTMLEscapeMap(sequence: "&minus;", code: 8722),
		HTMLEscapeMap(sequence: "&lowast;", code: 8727),
		HTMLEscapeMap(sequence: "&radic;", code: 8730),
		HTMLEscapeMap(sequence: "&prop;", code: 8733),
		HTMLEscapeMap(sequence: "&infin;", code: 8734),
		HTMLEscapeMap(sequence: "&ang;", code: 8736),
		HTMLEscapeMap(sequence: "&and;", code: 8743),
		HTMLEscapeMap(sequence: "&or;", code: 8744),
		HTMLEscapeMap(sequence: "&cap;", code: 8745),
		HTMLEscapeMap(sequence: "&cup;", code: 8746),
		HTMLEscapeMap(sequence: "&int;", code: 8747),
		HTMLEscapeMap(sequence: "&there4;", code: 8756),
		HTMLEscapeMap(sequence: "&sim;", code: 8764),
		HTMLEscapeMap(sequence: "&cong;", code: 8773),
		HTMLEscapeMap(sequence: "&asymp;", code: 8776),
		HTMLEscapeMap(sequence: "&ne;", code: 8800),
		HTMLEscapeMap(sequence: "&equiv;", code: 8801),
		HTMLEscapeMap(sequence: "&le;", code: 8804),
		HTMLEscapeMap(sequence: "&ge;", code: 8805),
		HTMLEscapeMap(sequence: "&sub;", code: 8834),
		HTMLEscapeMap(sequence: "&sup;", code: 8835),
		HTMLEscapeMap(sequence: "&nsub;", code: 8836),
		HTMLEscapeMap(sequence: "&sube;", code: 8838),
		HTMLEscapeMap(sequence: "&supe;", code: 8839),
		HTMLEscapeMap(sequence: "&oplus;", code: 8853),
		HTMLEscapeMap(sequence: "&otimes;", code: 8855),
		HTMLEscapeMap(sequence: "&perp;", code: 8869),
		HTMLEscapeMap(sequence: "&sdot;", code: 8901),
		HTMLEscapeMap(sequence: "&lceil;", code: 8968),
		HTMLEscapeMap(sequence: "&rceil;", code: 8969),
		HTMLEscapeMap(sequence: "&lfloor;", code: 8970),
		HTMLEscapeMap(sequence: "&rfloor;", code: 8971),
		HTMLEscapeMap(sequence: "&lang;", code: 9001),
		HTMLEscapeMap(sequence: "&rang;", code: 9002),
		HTMLEscapeMap(sequence: "&loz;", code: 9674),
		HTMLEscapeMap(sequence: "&spades;", code: 9824),
		HTMLEscapeMap(sequence: "&clubs;", code: 9827),
		HTMLEscapeMap(sequence: "&hearts;", code: 9829),
		HTMLEscapeMap(sequence: "&diams;", code: 9830),
	]
}
