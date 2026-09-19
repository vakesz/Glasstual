// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One `MODE` command's arguments after the channel name.

 A mode change is a mode string and the parameters that pair with it, and the
 two are separate tokens on the wire. Carrying them as one space-joined string
 meant the compiler built `"+ooo alice bob carol"` and `sendModes` took it apart
 again with the wire tokeniser — a round trip through text whose only job was to
 be undone, and one that could not carry a parameter containing a space. */
nonisolated struct ModeChangeGroup: Sendable, Equatable {
	/// The mode string, signs included: `+ooo`, `-k+l`, `+nt`.
	var symbols: String
	/// The parameters the mode string's letters pair with, in order.
	var parameters: [String]

	init(symbols: String, parameters: [String] = []) {
		self.symbols = symbols
		self.parameters = parameters
	}

	/// The group as the wire arguments that follow the channel name.
	var wireArguments: [String] {
		[symbols] + parameters
	}
}

nonisolated enum ModeParser {
	/** The channel modes RFC 1459 2.3 defines, for a server that has not said
	 which it has.

	 `CHANMODES` arrives in 005, which is after the session has already joined
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
	 here, `ISupport.modeHasParameter` — asks through this, because a
	 second copy of the rule is a second answer. */
	static func effectiveChannelModeKinds(
		_ channelModeKinds: [Character: ChannelModeKind]
	) -> [Character: ChannelModeKind] {
		let hasAdvertisedChannelModes = channelModeKinds.values.contains { $0 != .userPrefix }

		guard hasAdvertisedChannelModes == false else {
			return channelModeKinds
		}

		return rfc1459ChannelModeKinds.merging(channelModeKinds) { _, advertised in advertised }
	}

	static func parse(
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
}

extension ServerSession {
	func compileListOfModeChanges(
		forModeSymbol modeSymbol: String,
		modeIsSet: Bool,
		parameterString: String
	) -> [ModeChangeGroup] {
		compileListOfModeChanges(
			forModeSymbol: modeSymbol,
			modeIsSet: modeIsSet,
			modeParameters: parameterString.components(separatedBy: .whitespaces)
		)
	}

	func compileListOfModeChanges(
		forModeSymbol modeSymbol: String,
		modeIsSet: Bool,
		modeParameters: [String]
	) -> [ModeChangeGroup] {
		ModeParser.compileModeChanges(
			symbol: modeSymbol,
			isSet: modeIsSet,
			parameters: modeParameters,
			maximumModes: supportInfo.maximumModeCount
		)
	}
}
