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

/// Pure transformations used by `Client` at the wire and presentation
/// seams. Keeping these transformations independent of connection state makes
/// protocol output deterministic and directly testable.
nonisolated enum ClientWireUtilities { // nonisolated: value
	/// Ceiling on `%<width>n` style padding in the nickname format. The width
	/// comes from a user preference, so it needs a bound rather than trust.
	private static let maximumFormatPaddingWidth = 256
	/// The `MODE` commands that set or clear one mode over a list of parameters,
	/// or none when there is no single mode letter to change. The symbol can be
	/// one a server advertised and then withdrew, which is not a mode to send.
	///
	/// Structured rather than space-joined text: a mask or a key is a parameter
	/// of its own on the wire, and the caller that sends these has no business
	/// re-splitting a string this function had just assembled.
	static func compileModeChanges(
		symbol: String,
		isSet: Bool,
		parameters: [String],
		maximumModes: UInt
	) -> [ModeChangeGroup] {
		guard (symbol as NSString).length == 1 else {
			return []
		}

		var results: [ModeChangeGroup] = []
		var modeSymbols = ""
		var modeParameters: [String] = []

		func flush() {
			guard modeSymbols.isEmpty == false, modeParameters.isEmpty == false else {
				return
			}

			results.append(ModeChangeGroup(symbols: modeSymbols, parameters: modeParameters))
			modeSymbols = ""
			modeParameters.removeAll(keepingCapacity: true)
		}

		for parameter in parameters where parameter.isEmpty == false {
			if modeSymbols.isEmpty {
				modeSymbols = isSet ? "+\(symbol)" : "-\(symbol)"
			} else {
				modeSymbols += symbol
			}

			modeParameters.append(parameter)

			if maximumModes > 0, UInt(modeParameters.count) == maximumModes {
				flush()
			}
		}

		flush()

		return results
	}

	static func formatNickname(_ nickname: String, modeSymbol: String, format: String) -> String {
		let scanner = Scanner(string: format)
		scanner.charactersToBeSkipped = nil

		var output = ""

		while scanner.isAtEnd == false {
			if let literal = scanner.scanUpToString("%") {
				output += literal
			}

			guard scanner.scanString("%") != nil else {
				break
			}

			let paddingWidth = scanner.scanInt() ?? 0
			let substitution: String? = if scanner.scanString("@") != nil {
				modeSymbol
			} else if scanner.scanString("n") != nil {
				nickname
			} else if scanner.scanString("%") != nil {
				"%"
			} else {
				nil
			}

			guard let substitution else {
				continue
			}

			let substitutionLength = (substitution as NSString).length
			// `abs(Int.min)` traps, and no sane format asks for more padding
			// than a line can hold, so the magnitude is clamped instead.
			let requestedWidth = Int(min(paddingWidth.magnitude, UInt(maximumFormatPaddingWidth)))
			let padding = String(repeating: " ", count: max(0, requestedWidth - substitutionLength))

			if paddingWidth < 0 {
				output += padding
			}

			output += substitution

			if paddingWidth > 0 {
				output += padding
			}
		}

		return output
	}

	/// Truncates `text` to at most `maximumByteCount` UTF-8 bytes without
	/// splitting a character. A `maximumByteCount` of zero means no limit.
	///
	/// ISUPPORT `AWAYLEN`, `KICKLEN` and `TOPICLEN` are byte budgets, so
	/// measuring them in UTF-16 code units under-counts every non-ASCII
	/// string and lets the server do the truncating instead.
	static func truncated(_ text: String, toByteCount maximumByteCount: Int) -> String {
		guard maximumByteCount > 0, text.utf8.count > maximumByteCount else {
			return text
		}

		var truncated = ""
		var byteCount = 0

		for character in text {
			let characterBytes = String(character).utf8.count

			guard byteCount + characterBytes <= maximumByteCount else {
				break
			}

			byteCount += characterBytes
			truncated.append(character)
		}

		return truncated
	}

	/// The one command name every chat-history request goes out under.
	static let chatHistoryCommand = "CHATHISTORY"

	static func netsplitNicknameList(_ nicknames: [String], limit: UInt) -> String {
		guard UInt(nicknames.count) > limit else {
			return nicknames.joined(separator: ", ")
		}

		let shown = nicknames.prefix(Int(limit)).joined(separator: ", ")

		return InboundStrings.History.abbreviatedNicknames(
			shown,
			remaining: UInt(nicknames.count - Int(limit))
		)
	}
}
