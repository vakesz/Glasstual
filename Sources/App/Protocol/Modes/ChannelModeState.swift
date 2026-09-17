// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

final class ChannelModeState {
	private weak var client: Client?
	private weak var channel: Channel?

	private(set) var modes: ChannelModeContainer

	init(channel: Channel) {
		guard let associatedClient = channel.associatedClient else {
			fatalError("ChannelModeState requires an associated client")
		}

		client = associatedClient
		self.channel = channel
		modes = ChannelModeContainer(client: associatedClient)
	}

	func updateModes(_ modeString: String) -> [ModeInfo] {
		guard let client else {
			return []
		}

		let parsedModes = client.supportInfo.parseModes(modeString)

		modes.apply(parsedModes)

		return parsedModes
	}

	/** The `MODE` change that takes the channel from its current modes to `modes`.

	 Only a real difference is sent. A mode unset on both sides — including one
	 the channel never had, which the modes sheet writes for every checkbox left
	 clear — is no change at all, and a set mode whose parameter did not change
	 is not re-sent.

	 Whether a letter carries a parameter is the server's `CHANMODES` class, not
	 whether the container happens to hold text for it: `-l` takes none even
	 where the sheet still remembers the old limit, and `-k` takes one even where
	 it does not. Appending every stored parameter shifted the pairing, so
	 `-l+k 50 new` set the key to `50`. A removal is paired with the parameter the
	 channel was set with, which is what a server that checks `-k` compares; a
	 parameterised addition with no text cannot be expressed and is left out.

	 Returns no group where nothing changed. */
	func changeGroups(for modes: ChannelModeContainer) -> [ModeChangeGroup] {
		guard let client else {
			return []
		}

		let modesOld = self.modes.modes
		let modesNew = modes.modes
		let modeKinds = ModeParser.effectiveChannelModeKinds(client.supportInfo.channelModeKinds)

		var removedSymbols = ""
		var removedParameters: [String] = []
		var addedSymbols = ""
		var addedParameters: [String] = []

		for modeSymbol in Set(modesOld.keys).union(modesNew.keys).sorted() {
			guard let symbol = modeSymbol.first else {
				continue
			}

			let modeOld = modesOld[modeSymbol]
			let modeNew = modesNew[modeSymbol]
			let wasSet = modeOld?.modeIsSet == true
			let isSet = modeNew?.modeIsSet == true
			let policy = modeKinds[symbol]?.parameterPolicy ?? .never

			switch (wasSet, isSet) {
			case (false, false):
				continue
			case (true, false):
				removedSymbols += modeSymbol

				if policy.requiresParameter(whenModeIsSet: false) {
					removedParameters.append(
						Self.nonEmpty(modeOld?.modeParameter)
							?? Self.nonEmpty(modeNew?.modeParameter)
							?? Self.unknownRemovalParameter
					)
				}
			case (_, true):
				let requiresParameter = policy.requiresParameter(whenModeIsSet: true)
				let parameter = Self.nonEmpty(modeNew?.modeParameter)

				if wasSet, requiresParameter == false || parameter == Self.nonEmpty(modeOld?.modeParameter) {
					continue
				}

				if requiresParameter {
					guard let parameter else {
						continue
					}

					addedParameters.append(parameter)
				}

				addedSymbols += modeSymbol
			}
		}

		var symbols = ""

		if removedSymbols.isEmpty == false {
			symbols += "-" + removedSymbols
		}

		if addedSymbols.isEmpty == false {
			symbols += "+" + addedSymbols
		}

		guard symbols.isEmpty == false else {
			return []
		}

		return [ModeChangeGroup(symbols: symbols, parameters: removedParameters + addedParameters)]
	}

	/// What `-k` is paired with when nobody knows the key: servers that do not
	/// check it accept anything, and a missing token would shift every later
	/// parameter.
	private static let unknownRemovalParameter = "*"

	private static func nonEmpty(_ string: String?) -> String? {
		guard let string, string.isEmpty == false else {
			return nil
		}

		return string
	}

	func clear() {
		modes.clear()
	}

	func modeIsDefined(_ modeSymbol: String) -> Bool {
		modes.modeIsDefined(modeSymbol)
	}

	func modeInfo(for modeSymbol: String) -> ModeInfo? {
		modes.modeInfo(for: modeSymbol)
	}

	var string: String {
		string(maskingPassword: false)
	}

	var stringWithMaskedPassword: String {
		string(maskingPassword: true)
	}

	private func string(maskingPassword: Bool) -> String {
		var modeSetString = ""
		var modeParamString = ""

		for modeSymbol in sortedSymbols(modes.modes) {
			guard let mode = modes.modes[modeSymbol], mode.modeIsSet else {
				continue
			}

			if modeSetString.isEmpty {
				modeSetString = "+\(modeSymbol)"
			} else {
				modeSetString += modeSymbol
			}

			guard let modeParameter = mode.modeParameter, modeParameter.isEmpty == false else {
				continue
			}

			if modeSymbol == "k", maskingPassword {
				modeParamString += " ******"
			} else {
				modeParamString += " \(modeParameter)"
			}
		}

		return modeSetString + modeParamString
	}

	private func sortedSymbols(_ modes: [String: ModeInfo]) -> [String] {
		modes.keys.sorted()
	}
}

final class ChannelModeContainer: NSObject, NSCopying {
	private weak var client: Client?
	private var modeObjects: [String: ModeInfo] = [:]

	init(client: Client?) {
		self.client = client
		super.init()
	}

	func clear() {
		modeObjects.removeAll()
	}

	var modes: [String: ModeInfo] {
		modeObjects
	}

	/// The list modes this container refuses to hold, because their contents
	/// belong to the ban-list sheet rather than to the channel's mode string.
	/// A list the server does not support contributes no symbol at all.
	private var unwantedModes: [String] {
		guard let supportInfo = client?.supportInfo else {
			return []
		}

		return [ISupportListType.ban, .banException, .inviteException, .quiet]
			.compactMap { supportInfo.modeSymbol(forList: $0) }
	}

	private func modeIsPermitted(_ modeSymbol: String) -> Bool {
		if unwantedModes.contains(modeSymbol) {
			return false
		}

		if client?.supportInfo.modeSymbolIsUserPrefix(modeSymbol) == true {
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

	func apply(_ modes: [ModeInfo]) {
		for mode in modes {
			changeMode(mode.modeSymbol, modeIsSet: mode.modeIsSet, modeParameter: mode.modeParameter)
		}
	}

	func changeMode(_ modeSymbol: String, modeIsSet: Bool) {
		changeMode(modeSymbol, modeIsSet: modeIsSet, modeParameter: nil)
	}

	func changeMode(_ modeSymbol: String, modeIsSet: Bool, modeParameter: String?) {
		guard modeIsPermitted(modeSymbol) else {
			return
		}

		let modeUpdated = ModeInfo(modeSymbol: modeSymbol, modeIsSet: modeIsSet, modeParameter: modeParameter)

		modeObjects[modeSymbol] = modeUpdated
	}

	func copy(with _: NSZone? = nil) -> Any {
		let object = ChannelModeContainer(client: client)
		object.modeObjects = modeObjects

		return object
	}
}
