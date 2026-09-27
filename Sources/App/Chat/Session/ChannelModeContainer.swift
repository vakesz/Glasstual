// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The modes a channel is set with, by symbol.

 A value: handing one out is handing out a copy, which is what the modes sheet
 edits while the channel keeps the modes the server last reported. The session
 reference is weak and stays live rather than being read once, because the
 lists a server refuses to hold in a mode string are named by an `ISUPPORT`
 that can arrive after the channel does. */
struct ChannelModeContainer {
	private weak var session: ServerSession?
	private var modeObjects: [String: ModeInfo] = [:]

	init(session: ServerSession?) {
		self.session = session
	}

	mutating func clear() {
		modeObjects.removeAll()
	}

	var modes: [String: ModeInfo] {
		modeObjects
	}

	/// The list modes this container refuses to hold, because their contents
	/// belong to the ban-list sheet rather than to the channel's mode string.
	/// A list the server does not support contributes no symbol at all.
	private var unwantedModes: [String] {
		guard let supportInfo = session?.supportInfo else {
			return []
		}

		return [ISupportListKind.ban, .banException, .inviteException, .quiet]
			.compactMap { supportInfo.modeSymbol(forList: $0) }
	}

	private func modeIsPermitted(_ modeSymbol: String) -> Bool {
		if unwantedModes.contains(modeSymbol) {
			return false
		}

		if session?.supportInfo.modeSymbolIsUserPrefix(modeSymbol) == true {
			return false
		}

		return true
	}

	func modeIsDefined(_ modeSymbol: String) -> Bool {
		modes[modeSymbol] != nil
	}

	/** A pure lookup. Materialising a placeholder here made the channel's change
	 command emit `-mode` for modes the channel never had. */
	func modeInfo(for modeSymbol: String) -> ModeInfo? {
		modeObjects[modeSymbol]
	}

	mutating func apply(_ modes: [ModeInfo]) {
		for mode in modes {
			changeMode(mode.modeSymbol, modeIsSet: mode.modeIsSet, modeParameter: mode.modeParameter)
		}
	}

	mutating func changeMode(_ modeSymbol: String, modeIsSet: Bool) {
		changeMode(modeSymbol, modeIsSet: modeIsSet, modeParameter: nil)
	}

	mutating func changeMode(_ modeSymbol: String, modeIsSet: Bool, modeParameter: String?) {
		guard modeIsPermitted(modeSymbol) else {
			return
		}

		let modeUpdated = ModeInfo(modeSymbol: modeSymbol, modeIsSet: modeIsSet, modeParameter: modeParameter)

		modeObjects[modeSymbol] = modeUpdated
	}
}
