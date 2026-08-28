/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_
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

@objc(IRCModeParser)
public final class ModeParser: NSObject {
	@available(*, unavailable)
	override public init() {
		fatalError("ModeParser is a static namespace")
	}

	public static func parse(
		_ modeString: String,
		channelModeKinds: [Character: ChannelModeKind]
	) -> [ModeInfo] {
		let tokens = modeString.split(whereSeparator: { $0.isWhitespace }).map(String.init)
		var tokenIndex = 0
		var modeIsSet = false
		var modes: [ModeInfo] = []

		while tokenIndex < tokens.count {
			let token = tokens[tokenIndex]
			tokenIndex += 1

			guard token.first == "+" || token.first == "-" else {
				continue
			}

			modeIsSet = (token.first == "+")

			for character in token.dropFirst() {
				switch character {
				case "+":
					modeIsSet = true
				case "-":
					modeIsSet = false
				default:
					let policy = channelModeKinds[character]?.parameterPolicy ?? .never
					var modeParameter: String?

					if policy.requiresParameter(whenModeIsSet: modeIsSet), tokenIndex < tokens.count {
						modeParameter = tokens[tokenIndex]
						tokenIndex += 1
					}

					modes.append(
						ModeInfo(
							modeSymbol: String(character),
							modeIsSet: modeIsSet,
							modeParameter: modeParameter
						)
					)
				}
			}
		}

		return modes
	}
}
