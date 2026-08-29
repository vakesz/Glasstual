/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2006 - 2008 Google Inc.
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Licensed under the Apache License, Version 2.0
 *
 *********************************************************************** */

import Foundation

/// The entity to write for each scalar that must not appear literally in
/// markup. Keyed lookup replaces a binary search over an array that had to stay
/// sorted by an invariant nothing checked.
private nonisolated let entitiesByScalarValue: [UInt32: String] = [ // nonisolated: let
	34: "&quot;",
	38: "&amp;",
	39: "&apos;",
	60: "&lt;",
	62: "&gt;",
	338: "&OElig;",
	339: "&oelig;",
	352: "&Scaron;",
	353: "&scaron;",
	376: "&Yuml;",
	710: "&circ;",
	732: "&tilde;",
	8194: "&ensp;",
	8195: "&emsp;",
	8201: "&thinsp;",
	8204: "&zwnj;",
	8205: "&zwj;",
	8206: "&lrm;",
	8207: "&rlm;",
	8211: "&ndash;",
	8212: "&mdash;",
	8216: "&lsquo;",
	8217: "&rsquo;",
	8218: "&sbquo;",
	8220: "&ldquo;",
	8221: "&rdquo;",
	8222: "&bdquo;",
	8224: "&dagger;",
	8225: "&Dagger;",
	8240: "&permil;",
	8249: "&lsaquo;",
	8250: "&rsaquo;",
	8364: "&euro;",
]

/// Every named entity the unescaper understands, keyed by the whole `&name;`
/// spelling. This used to be scanned linearly, once per entity found.
private nonisolated let scalarValuesByEntity: [String: UInt32] = [ // nonisolated: let
	"&quot;": 34,
	"&amp;": 38,
	"&apos;": 39,
	"&lt;": 60,
	"&gt;": 62,
	"&nbsp;": 160,
	"&iexcl;": 161,
	"&cent;": 162,
	"&pound;": 163,
	"&curren;": 164,
	"&yen;": 165,
	"&brvbar;": 166,
	"&sect;": 167,
	"&uml;": 168,
	"&copy;": 169,
	"&ordf;": 170,
	"&laquo;": 171,
	"&not;": 172,
	"&shy;": 173,
	"&reg;": 174,
	"&macr;": 175,
	"&deg;": 176,
	"&plusmn;": 177,
	"&sup2;": 178,
	"&sup3;": 179,
	"&acute;": 180,
	"&micro;": 181,
	"&para;": 182,
	"&middot;": 183,
	"&cedil;": 184,
	"&sup1;": 185,
	"&ordm;": 186,
	"&raquo;": 187,
	"&frac14;": 188,
	"&frac12;": 189,
	"&frac34;": 190,
	"&iquest;": 191,
	"&Agrave;": 192,
	"&Aacute;": 193,
	"&Acirc;": 194,
	"&Atilde;": 195,
	"&Auml;": 196,
	"&Aring;": 197,
	"&AElig;": 198,
	"&Ccedil;": 199,
	"&Egrave;": 200,
	"&Eacute;": 201,
	"&Ecirc;": 202,
	"&Euml;": 203,
	"&Igrave;": 204,
	"&Iacute;": 205,
	"&Icirc;": 206,
	"&Iuml;": 207,
	"&ETH;": 208,
	"&Ntilde;": 209,
	"&Ograve;": 210,
	"&Oacute;": 211,
	"&Ocirc;": 212,
	"&Otilde;": 213,
	"&Ouml;": 214,
	"&times;": 215,
	"&Oslash;": 216,
	"&Ugrave;": 217,
	"&Uacute;": 218,
	"&Ucirc;": 219,
	"&Uuml;": 220,
	"&Yacute;": 221,
	"&THORN;": 222,
	"&szlig;": 223,
	"&agrave;": 224,
	"&aacute;": 225,
	"&acirc;": 226,
	"&atilde;": 227,
	"&auml;": 228,
	"&aring;": 229,
	"&aelig;": 230,
	"&ccedil;": 231,
	"&egrave;": 232,
	"&eacute;": 233,
	"&ecirc;": 234,
	"&euml;": 235,
	"&igrave;": 236,
	"&iacute;": 237,
	"&icirc;": 238,
	"&iuml;": 239,
	"&eth;": 240,
	"&ntilde;": 241,
	"&ograve;": 242,
	"&oacute;": 243,
	"&ocirc;": 244,
	"&otilde;": 245,
	"&ouml;": 246,
	"&divide;": 247,
	"&oslash;": 248,
	"&ugrave;": 249,
	"&uacute;": 250,
	"&ucirc;": 251,
	"&uuml;": 252,
	"&yacute;": 253,
	"&thorn;": 254,
	"&yuml;": 255,
	"&OElig;": 338,
	"&oelig;": 339,
	"&Scaron;": 352,
	"&scaron;": 353,
	"&Yuml;": 376,
	"&fnof;": 402,
	"&circ;": 710,
	"&tilde;": 732,
	"&Alpha;": 913,
	"&Beta;": 914,
	"&Gamma;": 915,
	"&Delta;": 916,
	"&Epsilon;": 917,
	"&Zeta;": 918,
	"&Eta;": 919,
	"&Theta;": 920,
	"&Iota;": 921,
	"&Kappa;": 922,
	"&Lambda;": 923,
	"&Mu;": 924,
	"&Nu;": 925,
	"&Xi;": 926,
	"&Omicron;": 927,
	"&Pi;": 928,
	"&Rho;": 929,
	"&Sigma;": 931,
	"&Tau;": 932,
	"&Upsilon;": 933,
	"&Phi;": 934,
	"&Chi;": 935,
	"&Psi;": 936,
	"&Omega;": 937,
	"&alpha;": 945,
	"&beta;": 946,
	"&gamma;": 947,
	"&delta;": 948,
	"&epsilon;": 949,
	"&zeta;": 950,
	"&eta;": 951,
	"&theta;": 952,
	"&iota;": 953,
	"&kappa;": 954,
	"&lambda;": 955,
	"&mu;": 956,
	"&nu;": 957,
	"&xi;": 958,
	"&omicron;": 959,
	"&pi;": 960,
	"&rho;": 961,
	"&sigmaf;": 962,
	"&sigma;": 963,
	"&tau;": 964,
	"&upsilon;": 965,
	"&phi;": 966,
	"&chi;": 967,
	"&psi;": 968,
	"&omega;": 969,
	"&thetasym;": 977,
	"&upsih;": 978,
	"&piv;": 982,
	"&ensp;": 8194,
	"&emsp;": 8195,
	"&thinsp;": 8201,
	"&zwnj;": 8204,
	"&zwj;": 8205,
	"&lrm;": 8206,
	"&rlm;": 8207,
	"&ndash;": 8211,
	"&mdash;": 8212,
	"&lsquo;": 8216,
	"&rsquo;": 8217,
	"&sbquo;": 8218,
	"&ldquo;": 8220,
	"&rdquo;": 8221,
	"&bdquo;": 8222,
	"&dagger;": 8224,
	"&Dagger;": 8225,
	"&bull;": 8226,
	"&hellip;": 8230,
	"&permil;": 8240,
	"&prime;": 8242,
	"&Prime;": 8243,
	"&lsaquo;": 8249,
	"&rsaquo;": 8250,
	"&oline;": 8254,
	"&frasl;": 8260,
	"&euro;": 8364,
	"&image;": 8465,
	"&weierp;": 8472,
	"&real;": 8476,
	"&trade;": 8482,
	"&alefsym;": 8501,
	"&larr;": 8592,
	"&uarr;": 8593,
	"&rarr;": 8594,
	"&darr;": 8595,
	"&harr;": 8596,
	"&crarr;": 8629,
	"&lArr;": 8656,
	"&uArr;": 8657,
	"&rArr;": 8658,
	"&dArr;": 8659,
	"&hArr;": 8660,
	"&forall;": 8704,
	"&part;": 8706,
	"&exist;": 8707,
	"&empty;": 8709,
	"&nabla;": 8711,
	"&isin;": 8712,
	"&notin;": 8713,
	"&ni;": 8715,
	"&prod;": 8719,
	"&sum;": 8721,
	"&minus;": 8722,
	"&lowast;": 8727,
	"&radic;": 8730,
	"&prop;": 8733,
	"&infin;": 8734,
	"&ang;": 8736,
	"&and;": 8743,
	"&or;": 8744,
	"&cap;": 8745,
	"&cup;": 8746,
	"&int;": 8747,
	"&there4;": 8756,
	"&sim;": 8764,
	"&cong;": 8773,
	"&asymp;": 8776,
	"&ne;": 8800,
	"&equiv;": 8801,
	"&le;": 8804,
	"&ge;": 8805,
	"&sub;": 8834,
	"&sup;": 8835,
	"&nsub;": 8836,
	"&sube;": 8838,
	"&supe;": 8839,
	"&oplus;": 8853,
	"&otimes;": 8855,
	"&perp;": 8869,
	"&sdot;": 8901,
	"&lceil;": 8968,
	"&rceil;": 8969,
	"&lfloor;": 8970,
	"&rfloor;": 8971,
	"&lang;": 9001,
	"&rang;": 9002,
	"&loz;": 9674,
	"&spades;": 9824,
	"&clubs;": 9827,
	"&hearts;": 9829,
	"&diams;": 9830,
]

/// Longest named entity in the table above, so a `&`...`;` run longer than this
/// can be rejected without a lookup.
private nonisolated let maximumEntityLength = 10 // nonisolated: let

public nonisolated extension String { // nonisolated: value
	/// The receiver with every character that would otherwise be markup written
	/// as an HTML entity.
	///
	/// Scalars are examined one at a time and an entity is never re-examined,
	/// so the result cannot be double-escaped.
	var escapingForHTML: String {
		guard !isEmpty else {
			return self
		}

		var result = ""
		result.reserveCapacity(count)

		for scalar in unicodeScalars {
			if let entity = entitiesByScalarValue[scalar.value] {
				result += entity
			} else {
				result.unicodeScalars.append(scalar)
			}
		}

		return result
	}

	/// The receiver with named entities (`&amp;`) and numeric character
	/// references (`&#38;`, `&#x26;`) resolved. Anything that does not parse is
	/// left exactly as written.
	var unescapingFromHTML: String {
		guard contains("&") else {
			return self
		}

		var result = ""
		result.reserveCapacity(count)

		var cursor = startIndex

		while let ampersand = self[cursor...].firstIndex(of: "&") {
			result += self[cursor ..< ampersand]
			cursor = ampersand

			/* Bounding the window bounds the search: nothing longer than the
			 longest entity can be one. */
			let window = self[ampersand...].prefix(maximumEntityLength)

			guard
				let semicolon = window.firstIndex(of: ";"),
				let scalar = Self.entityScalar(in: self[ampersand ... semicolon])
			else {
				result.append(self[ampersand])
				cursor = index(after: ampersand)
				continue
			}

			result.unicodeScalars.append(scalar)
			cursor = index(after: semicolon)
		}

		result += self[cursor...]
		return result
	}

	/// The scalar `entity` -- a full `&`...`;` run -- stands for, or `nil` when
	/// it is not an entity this understands.
	private static func entityScalar(in entity: Substring) -> Unicode.Scalar? {
		if let value = scalarValuesByEntity[String(entity)] {
			return Unicode.Scalar(value)
		}

		var digits = entity.dropFirst().dropLast()

		guard digits.hasPrefix("#") else {
			return nil
		}

		digits = digits.dropFirst()
		let radix: Int

		if digits.hasPrefix("x") || digits.hasPrefix("X") {
			digits = digits.dropFirst()
			radix = 16
		} else {
			radix = 10
		}

		guard let value = UInt32(digits, radix: radix), value > 0 else {
			return nil
		}

		return Unicode.Scalar(value)
	}
}
