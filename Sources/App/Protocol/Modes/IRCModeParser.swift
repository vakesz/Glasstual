/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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

public final class ModeParser: NSObject {
	@available(*, unavailable)
	override public init() {
		fatalError("ModeParser is a static namespace")
	}

	/** The channel modes RFC 1459 2.3 defines, for a server that has not said
	 which it has.

	 `CHANMODES` arrives in 005, which is after the client has already joined
	 nothing and before it has joined anything — but a server may never send one
	 at all, and a `MODE` or `RPL_CHANNELMODEIS` can arrive before it does. With
	 no table every letter parsed as a plain flag, so `+b nick!*@*` recorded a
	 ban with no mask and then read the mask as another run of modes, and
	 `+kl secret 50` lost both the key and the limit. `e` and `I` are listed
	 because a server that supports them and advertises nothing at all still
	 parameterises them; one that advertises `CHANMODES` overrides every letter
	 it names. */
	static let rfc1459ChannelModeKinds: [Character: ChannelModeKind] = [
		"b": .list, "e": .list, "I": .list,
		"k": .setting,
		"l": .settingWhenSet,
		"i": .flag, "m": .flag, "n": .flag, "p": .flag, "s": .flag, "t": .flag,
	]

	/** `channelModeKinds` with the RFC 1459 table standing in where the server
	 has advertised no `CHANMODES` of its own.

	 The one place that decision is made. A table holding nothing but the
	 `PREFIX` modes is one no `CHANMODES` has been read into yet; once one has,
	 the server's answer stands even where it is narrower than the RFC's.
	 Anything that has to know whether a mode takes a parameter — the parser
	 here, `IRCISupportInfo.modeHasParameter` — asks through this, because a
	 second copy of the rule is a second answer. */
	public static func effectiveChannelModeKinds(
		_ channelModeKinds: [Character: ChannelModeKind]
	) -> [Character: ChannelModeKind] {
		let hasAdvertisedChannelModes = channelModeKinds.values.contains { $0 != .userPrefix }

		guard hasAdvertisedChannelModes == false else {
			return channelModeKinds
		}

		return rfc1459ChannelModeKinds.merging(channelModeKinds) { _, advertised in advertised }
	}

	public static func parse(
		_ modeString: String,
		channelModeKinds: [Character: ChannelModeKind]
	) -> [ModeInfo] {
		let modeKinds = effectiveChannelModeKinds(channelModeKinds)

		/* RFC 1459/2812 separate tokens on SPACE only. Splitting on the wider
		 Unicode set would cut a mode parameter that legitimately contains one. */
		let tokens = LineParser.wireTokens(in: modeString)
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
					let policy = modeKinds[character]?.parameterPolicy ?? .never
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
