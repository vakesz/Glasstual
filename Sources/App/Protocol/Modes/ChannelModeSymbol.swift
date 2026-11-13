// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One channel-user mode letter, as advertised through ISUPPORT `PREFIX`.
///
/// Which letters exist is the server's to decide, so this carries no cases of
/// its own; it exists so that a mode is not passed around as a `String` that
/// might hold none, one or several of them.
nonisolated struct ChannelModeSymbol: Hashable, Sendable, CustomStringConvertible {
	let character: Character

	init(_ character: Character) {
		self.character = character
	}

	/// Reads exactly one mode letter, or nothing.
	init?(_ text: String) {
		guard text.count == 1, let character = text.first else {
			return nil
		}

		self.init(character)
	}

	var description: String {
		String(character)
	}
}

/// The membership modes one channel member holds, highest rank first.
///
/// A member's modes used to be a bare `String` that every reader sliced by
/// hand: the first character was the mark, `contains` answered membership, and
/// the ordering was maintained by rebuilding the string at the one site that
/// added a mode. The order comes from `PREFIX`, so it is the server's, and the
/// type keeps it.
nonisolated struct ChannelModeSymbolSet: Hashable, Sendable {
	private var symbols: [ChannelModeSymbol]

	init() {
		symbols = []
	}

	init(_ symbols: some Sequence<ChannelModeSymbol>) {
		var seen: Set<ChannelModeSymbol> = []

		self.symbols = symbols.filter { seen.insert($0).inserted }
	}

	/// Reads a run of mode letters in the order they are written, which is the
	/// order the server ranked them.
	init(letters: String) {
		self.init(letters.map(ChannelModeSymbol.init))
	}

	/// The modes as a run of letters, the form the wire and the stored
	/// configuration use.
	var letters: String {
		String(symbols.map(\.character))
	}

	var isEmpty: Bool {
		symbols.isEmpty
	}

	/// The highest-ranked mode, which is the one a member is marked with.
	var highest: ChannelModeSymbol? {
		symbols.first
	}

	func contains(_ symbol: ChannelModeSymbol) -> Bool {
		symbols.contains(symbol)
	}

	mutating func remove(_ symbol: ChannelModeSymbol) {
		symbols.removeAll { $0 == symbol }
	}

	/// Inserts `symbol` where `rank` puts it, keeping the highest first. A mode
	/// the member already holds is left where it is.
	mutating func insert(_ symbol: ChannelModeSymbol, rankedBy rank: (ChannelModeSymbol) -> UInt) {
		guard contains(symbol) == false else {
			return
		}

		let newRank = rank(symbol)
		let index = symbols.firstIndex { rank($0) < newRank } ?? symbols.endIndex

		symbols.insert(symbol, at: index)
	}
}

nonisolated extension ChannelModeSymbolSet: Sequence {
	func makeIterator() -> IndexingIterator<[ChannelModeSymbol]> {
		symbols.makeIterator()
	}
}

nonisolated extension ChannelModeSymbolSet: ExpressibleByStringLiteral {
	init(stringLiteral value: String) {
		self.init(letters: value)
	}
}

nonisolated extension ChannelModeSymbolSet: CustomStringConvertible {
	var description: String {
		letters
	}
}
