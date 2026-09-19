// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Fitting mode changes into the `MODE` commands a server will take.

 A change is a mode string and the parameters that pair with it. What varies is
 how many of those pairs one command may carry: `MODES` from ISUPPORT caps the
 count and the line length caps the bytes, so one change becomes as many
 commands as it needs. Sending a change whole made the server read
 `+ooo alice bob carol` as a single parameter and op nobody. */
nonisolated enum OutboundModeCommands {
	/// The groups `tokens` — a mode string and its parameters as the user or a
	/// sheet wrote them — describe, before any splitting.
	///
	/// `/umode +s +cfk` is two independent changes, and a server that reads only
	/// the first mode string of a line would silently drop the second if they
	/// shared one.
	///
	/// A token is read as a new mode string only once the letters before it have
	/// had the parameters they are owed: `+k +secret` sets the key `+secret`, and
	/// reading it as a second mode string sent a bare `+k` and then `+secret`.
	///
	/// - Parameter modeTakesParameter: Whether a letter, set or unset, is paired
	///   with a parameter on this target.
	static func groups(
		inTokens tokens: [String],
		modeTakesParameter: (_ symbol: Character, _ modeIsSet: Bool) -> Bool
	) -> [ModeChangeGroup] {
		var result: [ModeChangeGroup] = []
		var parametersOwed = 0

		for token in tokens where token.isEmpty == false {
			if parametersOwed > 0 {
				result[result.count - 1].parameters.append(token)
				parametersOwed -= 1
			} else if isModeString(token) || result.isEmpty {
				result.append(ModeChangeGroup(symbols: token))
				parametersOwed = modeChanges(in: token).count { change in
					modeTakesParameter(change.symbol, change.sign == "+")
				}
			} else {
				result[result.count - 1].parameters.append(token)
			}
		}

		return result
	}

	private static func isModeString(_ token: String) -> Bool {
		token.hasPrefix("+") || token.hasPrefix("-")
	}

	/// `group` cut into the commands one server will take.
	///
	/// - Parameters:
	///   - maximumModes: `MODES` from ISUPPORT — how many parameterised changes
	///     one command takes. Zero means the server named no limit.
	///   - budget: The bytes left for these arguments once the command name and
	///     the channel are charged.
	static func groups(for group: ModeChangeGroup, maximumModes: UInt, budget: Int) -> [ModeChangeGroup] {
		let changes = modeChanges(in: group.symbols)

		/* Only a mode string whose every letter has a parameter can be split:
		 the letters pair up with the parameters one for one, so any prefix of
		 the pairs is a valid command. Anything else — a bare `+nt`, a `-k+l`
		 the caller gave one parameter — goes out whole, because cutting it
		 would change which parameter belongs to which mode. */
		guard changes.count == group.parameters.count, changes.count > 1 else {
			return [group]
		}

		let pairs = zip(changes, group.parameters).map { (change: $0, parameter: $1) }
		let batches = WireBatching.pack(
			pairs,
			maximumCount: maximumModes > 0 ? Int(maximumModes) : 0,
			budget: budget,
			cost: { pair, batch in
				/* The rebuilt mode string repeats a sign only where it changes,
				 so a pair costs its sign only when it opens the batch or turns
				 it around. */
				let signCost = batch.last?.change.sign == pair.change.sign
					? 0 : String(pair.change.sign).utf8.count

				return signCost + String(pair.change.symbol).utf8.count + 1 + pair.parameter.utf8.count
			}
		)

		return batches.map { batch in
			ModeChangeGroup(
				symbols: modeString(for: batch.map(\.change)),
				parameters: batch.map(\.parameter)
			)
		}
	}

	/// The `(sign, symbol)` pairs a mode string names, in order.
	private static func modeChanges(in modeString: String) -> [(sign: Character, symbol: Character)] {
		var sign: Character = "+"
		var result: [(sign: Character, symbol: Character)] = []

		for character in modeString {
			if character == "+" || character == "-" {
				sign = character
			} else {
				result.append((sign: sign, symbol: character))
			}
		}

		return result
	}

	/// The pairs written back as a mode string, repeating a sign only where it
	/// changes.
	private static func modeString(for changes: [(sign: Character, symbol: Character)]) -> String {
		var result = ""
		var sign: Character?

		for change in changes {
			if change.sign != sign {
				result.append(change.sign)
				sign = change.sign
			}

			result.append(change.symbol)
		}

		return result
	}
}
