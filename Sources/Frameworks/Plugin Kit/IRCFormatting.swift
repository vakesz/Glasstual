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

/** IRC wire-format normalization shared by the host and bundled plugins. */
public enum IRCFormatting {
	private enum ControlCharacter {
		static let bold: UInt16 = 0x02
		static let colorDigit: UInt16 = 0x03
		static let colorHex: UInt16 = 0x04
		static let terminator: UInt16 = 0x0F
		static let monospace: UInt16 = 0x11
		static let legacyItalic: UInt16 = 0x16
		static let italic: UInt16 = 0x1D
		static let strikethrough: UInt16 = 0x1E
		static let underline: UInt16 = 0x1F
	}

	/** Removes mIRC formatting control sequences while preserving message text. */
	public static func removingControlCodes(from text: String) -> String {
		let input = Array(text.utf16)
		guard input.isEmpty == false else {
			return text
		}

		var output: [UInt16] = []
		output.reserveCapacity(input.count)

		var index = input.startIndex
		while index < input.endIndex {
			switch input[index] {
			case ControlCharacter.bold,
			     ControlCharacter.italic,
			     ControlCharacter.legacyItalic,
			     ControlCharacter.monospace,
			     ControlCharacter.strikethrough,
			     ControlCharacter.underline,
			     ControlCharacter.terminator:
				index += 1
			case ControlCharacter.colorDigit:
				index += digitColorSequenceLength(in: input, startingAt: index)
			case ControlCharacter.colorHex:
				index += hexadecimalColorSequenceLength(in: input, startingAt: index)
			default:
				output.append(input[index])
				index += 1
			}
		}

		return String(decoding: output, as: UTF16.self)
	}

	private static func digitColorSequenceLength(in input: [UInt16], startingAt startIndex: Int) -> Int {
		var index = startIndex + 1
		guard index < input.endIndex, input[index].isASCIIDigit else {
			return 1
		}

		index += 1
		if index < input.endIndex, input[index].isASCIIDigit {
			index += 1
		}

		guard index < input.endIndex, input[index] == 0x2C else {
			return index - startIndex
		}

		let commaIndex = index
		index += 1
		guard index < input.endIndex, input[index].isASCIIDigit else {
			return commaIndex - startIndex
		}

		index += 1
		if index < input.endIndex, input[index].isASCIIDigit {
			index += 1
		}

		return index - startIndex
	}

	private static func hexadecimalColorSequenceLength(in input: [UInt16], startingAt startIndex: Int) -> Int {
		let foregroundStart = startIndex + 1
		let foregroundEnd = foregroundStart + 6
		guard foregroundEnd <= input.endIndex,
		      input[foregroundStart ..< foregroundEnd].allSatisfy(\.isASCIIHexadecimalDigit)
		else {
			return 1
		}

		guard foregroundEnd < input.endIndex, input[foregroundEnd] == 0x2C else {
			return foregroundEnd - startIndex
		}

		let backgroundStart = foregroundEnd + 1
		let backgroundEnd = backgroundStart + 6
		guard backgroundEnd <= input.endIndex,
		      input[backgroundStart ..< backgroundEnd].allSatisfy(\.isASCIIHexadecimalDigit)
		else {
			return foregroundEnd - startIndex
		}

		return backgroundEnd - startIndex
	}
}

private extension UInt16 {
	var isASCIIDigit: Bool {
		(0x30 ... 0x39).contains(self)
	}

	var isASCIIHexadecimalDigit: Bool {
		isASCIIDigit || (0x41 ... 0x46).contains(self) || (0x61 ... 0x66).contains(self)
	}
}
