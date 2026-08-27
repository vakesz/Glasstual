/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

@objc(IRCChannelMode)
public final class ChannelModeState: NSObject {
	private weak var client: IRCClient?
	private weak var channel: IRCChannel?

	@objc public private(set) var modes: ChannelModeContainer

	@available(*, unavailable)
	override public init() {
		fatalError("Use ChannelModeState.init(channel:)")
	}

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		guard let associatedClient = channel.associatedClient else {
			fatalError("ChannelModeState requires an associated client")
		}

		client = associatedClient
		self.channel = channel
		modes = ChannelModeContainer(client: associatedClient)

		super.init()
	}

	@objc(updateModes:)
	public func updateModes(_ modeString: String) -> [ModeInfo] {
		let parsedModes = client!.supportInfo.parseModes(modeString)

		modes.apply(parsedModes)

		return parsedModes
	}

	@objc(getChangeCommand:)
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

			if let modeOld = modesSetOld[modeSymbol], mode.isEqual(modeOld) {
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

	@objc
	public func clear() {
		modes.clear()
	}

	@objc(modeIsDefined:)
	public func modeIsDefined(_ modeSymbol: String) -> Bool {
		modes.modeIsDefined(modeSymbol)
	}

	@objc(modeInfoFor:)
	public func modeInfo(for modeSymbol: String) -> ModeInfo? {
		modes.modeInfo(for: modeSymbol)
	}

	@objc public var string: String {
		string(maskingPassword: false)
	}

	@objc public var stringWithMaskedPassword: String {
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

@objc(IRCChannelModeContainer)
public final class ChannelModeContainer: NSObject, NSCopying {
	private weak var client: IRCClient?
	private let modeObjectsLock = NSLock()
	private var modeObjects: [String: ModeInfo] = [:]

	public init(client: IRCClient) {
		self.client = client
		super.init()
	}

	@objc
	public func clear() {
		modeObjectsLock.lock()
		modeObjects.removeAll()
		modeObjectsLock.unlock()
	}

	@objc public var modes: [String: ModeInfo] {
		modeObjectsLock.lock()
		let modes = modeObjects
		modeObjectsLock.unlock()
		return modes
	}

	private var unwantedModes: [String] {
		let supportInfo = client?.supportInfo

		return [
			supportInfo?.modeSymbol(forList: .ban) ?? "not supported: b",
			supportInfo?.modeSymbol(forList: .banException) ?? "not supported: e",
			supportInfo?.modeSymbol(forList: .inviteException) ?? "not supported: I",
			supportInfo?.modeSymbol(forList: .quiet) ?? "not supported: q",
		]
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

	@objc(modeIsDefined:)
	public func modeIsDefined(_ modeSymbol: String) -> Bool {
		modes[modeSymbol] != nil
	}

	@objc(modeInfoFor:)
	public func modeInfo(for modeSymbol: String) -> ModeInfo? {
		modeObjectsLock.lock()
		defer { modeObjectsLock.unlock() }

		if let mode = modeObjects[modeSymbol] {
			return mode
		}

		guard modeIsPermitted(modeSymbol) else {
			return nil
		}

		let mode = ModeInfo(modeSymbol: modeSymbol)

		modeObjects[modeSymbol] = mode

		return mode
	}

	@objc(applyModes:)
	public func apply(_ modes: [ModeInfo]) {
		for mode in modes {
			changeMode(mode.modeSymbol, modeIsSet: mode.modeIsSet, modeParameter: mode.modeParameter)
		}
	}

	@objc(changeMode:modeIsSet:)
	public func changeMode(_ modeSymbol: String, modeIsSet: Bool) {
		changeMode(modeSymbol, modeIsSet: modeIsSet, modeParameter: nil)
	}

	@objc(changeMode:modeIsSet:modeParameter:)
	public func changeMode(_ modeSymbol: String, modeIsSet: Bool, modeParameter: String?) {
		guard let mode = modeInfo(for: modeSymbol) else {
			return
		}

		guard let modeMutable = mode.mutableCopy() as? MutableModeInfo else {
			preconditionFailure("ModeInfo mutable copies must use MutableModeInfo")
		}

		modeMutable.modeSymbol = modeSymbol
		modeMutable.modeIsSet = modeIsSet
		modeMutable.modeParameter = modeParameter

		guard let modeUpdated = modeMutable.copy() as? ModeInfo else {
			preconditionFailure("MutableModeInfo copies must use ModeInfo")
		}

		modeObjectsLock.lock()
		modeObjects[modeSymbol] = modeUpdated
		modeObjectsLock.unlock()
	}

	public func copy(with _: NSZone? = nil) -> Any {
		let object = ChannelModeContainer(client: client!)

		modeObjectsLock.lock()
		let snapshot = modeObjects
		modeObjectsLock.unlock()

		object.modeObjectsLock.lock()
		object.modeObjects = snapshot
		object.modeObjectsLock.unlock()

		return object
	}
}
