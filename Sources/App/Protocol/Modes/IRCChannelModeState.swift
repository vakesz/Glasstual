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

public final class ChannelModeState: NSObject {
	private weak var client: IRCClient?
	private weak var channel: IRCChannel?

	public private(set) var modes: ChannelModeContainer

	@available(*, unavailable)
	override public init() {
		fatalError("Use ChannelModeState.init(channel:)")
	}

	public init(channel: IRCChannel) {
		guard let associatedClient = channel.associatedClient else {
			fatalError("ChannelModeState requires an associated client")
		}

		client = associatedClient
		self.channel = channel
		modes = ChannelModeContainer(client: associatedClient)

		super.init()
	}

	public func updateModes(_ modeString: String) -> [ModeInfo] {
		guard let client else {
			return []
		}

		let parsedModes = client.supportInfo.parseModes(modeString)

		modes.apply(parsedModes)

		return parsedModes
	}

	public func changeCommand(for modes: ChannelModeContainer) -> String {
		let modesSetOld = self.modes.modes
		let modesSetNew = modes.modes

		var modeAddString = ""
		var modeRemoveString = ""
		var modeRemoveParamString = ""
		var modeAddParamString = ""

		for modeSymbol in sortedSymbols(modesSetOld) where modesSetNew[modeSymbol] == nil {
			if modeRemoveString.isEmpty {
				modeRemoveString = "-\(modeSymbol)"
			} else {
				modeRemoveString += modeSymbol
			}
		}

		for modeSymbol in sortedSymbols(modesSetNew) {
			guard let mode = modesSetNew[modeSymbol] else {
				continue
			}

			if let modeOld = modesSetOld[modeSymbol], mode == modeOld {
				continue
			}

			if mode.modeIsSet {
				if modeAddString.isEmpty {
					modeAddString = "+\(modeSymbol)"
				} else {
					modeAddString += modeSymbol
				}
			} else {
				if modeRemoveString.isEmpty {
					modeRemoveString = "-\(modeSymbol)"
				} else {
					modeRemoveString += modeSymbol
				}
			}

			guard let modeParameter = mode.modeParameter, modeParameter.isEmpty == false else {
				continue
			}

			if mode.modeIsSet {
				modeAddParamString += " \(modeParameter)"
			} else {
				modeRemoveParamString += " \(modeParameter)"
			}
		}

		return modeRemoveString + modeAddString + modeRemoveParamString + modeAddParamString
	}

	public func clear() {
		modes.clear()
	}

	public func modeIsDefined(_ modeSymbol: String) -> Bool {
		modes.modeIsDefined(modeSymbol)
	}

	public func modeInfo(for modeSymbol: String) -> ModeInfo? {
		modes.modeInfo(for: modeSymbol)
	}

	public var string: String {
		string(maskingPassword: false)
	}

	public var stringWithMaskedPassword: String {
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

public final class ChannelModeContainer: NSObject, NSCopying {
	private weak var client: IRCClient?
	private var modeObjects: [String: ModeInfo] = [:]

	public init(client: IRCClient?) {
		self.client = client
		super.init()
	}

	public func clear() {
		modeObjects.removeAll()
	}

	public var modes: [String: ModeInfo] {
		modeObjects
	}

	/// The list modes this container refuses to hold, because their contents
	/// belong to the ban-list sheet rather than to the channel's mode string.
	/// A list the server does not support contributes no symbol at all.
	private var unwantedModes: [String] {
		guard let supportInfo = client?.supportInfo else {
			return []
		}

		return [IRCISupportInfoListType.ban, .banException, .inviteException, .quiet]
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

	public func modeIsDefined(_ modeSymbol: String) -> Bool {
		modes[modeSymbol] != nil
	}

	/** A pure lookup. Materialising a placeholder here made `changeCommand(for:)`
	 emit `-mode` for modes the channel never had. */
	public func modeInfo(for modeSymbol: String) -> ModeInfo? {
		modeObjects[modeSymbol]
	}

	public func apply(_ modes: [ModeInfo]) {
		for mode in modes {
			changeMode(mode.modeSymbol, modeIsSet: mode.modeIsSet, modeParameter: mode.modeParameter)
		}
	}

	public func changeMode(_ modeSymbol: String, modeIsSet: Bool) {
		changeMode(modeSymbol, modeIsSet: modeIsSet, modeParameter: nil)
	}

	public func changeMode(_ modeSymbol: String, modeIsSet: Bool, modeParameter: String?) {
		guard modeIsPermitted(modeSymbol) else {
			return
		}

		let modeUpdated = ModeInfo(modeSymbol: modeSymbol, modeIsSet: modeIsSet, modeParameter: modeParameter)

		modeObjects[modeSymbol] = modeUpdated
	}

	public func copy(with _: NSZone? = nil) -> Any {
		let object = ChannelModeContainer(client: client)
		object.modeObjects = modeObjects

		return object
	}
}
