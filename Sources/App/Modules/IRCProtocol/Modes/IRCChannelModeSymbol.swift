/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

/// One channel-user mode letter, as advertised through ISUPPORT `PREFIX`.
///
/// Which letters exist is the server's to decide, so this carries no cases of
/// its own; it exists so that a mode is not passed around as a `String` that
/// might hold none, one or several of them.
public nonisolated struct ChannelModeSymbol: Hashable, Sendable, CustomStringConvertible {
	public let character: Character

	public init(_ character: Character) {
		self.character = character
	}

	/// Reads exactly one mode letter, or nothing.
	public init?(_ text: String) {
		guard text.count == 1, let character = text.first else {
			return nil
		}

		self.init(character)
	}

	public var description: String {
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
public nonisolated struct ChannelModeSymbolSet: Hashable, Sendable {
	private var symbols: [ChannelModeSymbol]

	public init() {
		symbols = []
	}

	public init(_ symbols: some Sequence<ChannelModeSymbol>) {
		var seen: Set<ChannelModeSymbol> = []

		self.symbols = symbols.filter { seen.insert($0).inserted }
	}

	/// Reads a run of mode letters in the order they are written, which is the
	/// order the server ranked them.
	public init(letters: String) {
		self.init(letters.map(ChannelModeSymbol.init))
	}

	/// The modes as a run of letters, the form the wire and the stored
	/// configuration use.
	public var letters: String {
		String(symbols.map(\.character))
	}

	public var isEmpty: Bool {
		symbols.isEmpty
	}

	/// The highest-ranked mode, which is the one a member is marked with.
	public var highest: ChannelModeSymbol? {
		symbols.first
	}

	public func contains(_ symbol: ChannelModeSymbol) -> Bool {
		symbols.contains(symbol)
	}

	public mutating func remove(_ symbol: ChannelModeSymbol) {
		symbols.removeAll { $0 == symbol }
	}

	/// Inserts `symbol` where `rank` puts it, keeping the highest first. A mode
	/// the member already holds is left where it is.
	public mutating func insert(_ symbol: ChannelModeSymbol, rankedBy rank: (ChannelModeSymbol) -> UInt) {
		guard contains(symbol) == false else {
			return
		}

		let newRank = rank(symbol)
		let index = symbols.firstIndex { rank($0) < newRank } ?? symbols.endIndex

		symbols.insert(symbol, at: index)
	}
}

nonisolated extension ChannelModeSymbolSet: Sequence {
	public func makeIterator() -> IndexingIterator<[ChannelModeSymbol]> {
		symbols.makeIterator()
	}
}

nonisolated extension ChannelModeSymbolSet: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) {
		self.init(letters: value)
	}
}

nonisolated extension ChannelModeSymbolSet: CustomStringConvertible {
	public var description: String {
		letters
	}
}
