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

import CocoaExtensions
import Foundation

@objc(IRCModeInfo)
public class ModeInfo: PortablePropertyObject {
	fileprivate var isSetStorage: Bool
	fileprivate var symbolStorage: String
	fileprivate var parameterStorage: String?

	@objc public var modeIsSet: Bool {
		isSetStorage
	}

	@objc public var modeSymbol: String {
		symbolStorage
	}

	@objc public var modeParameter: String? {
		parameterStorage
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(modeSymbol:)")
	}

	@objc(initWithModeSymbol:)
	public convenience init(modeSymbol: String) {
		self.init(modeSymbol: modeSymbol, modeIsSet: false, modeParameter: nil)
	}

	@objc(initWithModeSymbol:modeIsSet:)
	public convenience init(modeSymbol: String, modeIsSet: Bool) {
		self.init(modeSymbol: modeSymbol, modeIsSet: modeIsSet, modeParameter: nil)
	}

	@objc(initWithModeSymbol:modeIsSet:modeParameter:)
	public init(modeSymbol: String, modeIsSet: Bool, modeParameter: String?) {
		precondition(modeSymbol.count == 1, "A mode symbol must contain exactly one character")

		isSetStorage = modeIsSet
		symbolStorage = modeSymbol
		parameterStorage = modeParameter

		super.init()
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	override public func copy(with _: NSZone? = nil) -> Any {
		if type(of: self) == ModeInfo.self {
			return self
		}

		return ModeInfo(copying: self)
	}

	override public func mutableCopy(with _: NSZone? = nil) -> Any {
		MutableModeInfo(copying: self)
	}

	override public func copy(asMutable mutableCopy: Bool) -> Any {
		copy(asMutable: mutableCopy, uniquing: false)
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing _: Bool) -> Any {
		mutableCopy ? MutableModeInfo(copying: self) : ModeInfo(copying: self)
	}

	override public func uniqueCopy(asMutable mutableCopy: Bool) -> Any {
		copy(asMutable: mutableCopy, uniquing: true)
	}

	override public func uniqueCopy() -> Any {
		ModeInfo(copying: self)
	}

	override public func uniqueCopyMutable() -> Any {
		MutableModeInfo(copying: self)
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? ModeInfo else {
			return false
		}

		return modeIsSet == other.modeIsSet && modeSymbol == other.modeSymbol && modeParameter == other.modeParameter
	}

	override public var hash: Int {
		var hasher = Hasher()
		hasher.combine(modeIsSet)
		hasher.combine(modeSymbol)
		hasher.combine(modeParameter)

		return hasher.finalize()
	}

	@objc(isModeForChangingMemberModeOn:)
	public func isModeForChangingMemberMode(on client: IRCClient) -> Bool {
		guard modeParameter?.isEmpty == false else {
			return false
		}

		return client.supportInfo.modeSymbolIsUserPrefix(modeSymbol)
	}

	fileprivate convenience init(copying mode: ModeInfo) {
		self.init(
			modeSymbol: mode.modeSymbol,
			modeIsSet: mode.modeIsSet,
			modeParameter: mode.modeParameter
		)
	}
}

@objc(IRCModeInfoMutable)
public final class MutableModeInfo: ModeInfo {
	override public static var isMutable: Bool {
		true
	}

	@objc override public var modeIsSet: Bool {
		get { isSetStorage }
		set { isSetStorage = newValue }
	}

	@objc override public var modeSymbol: String {
		get { symbolStorage }
		set {
			precondition(newValue.count == 1, "A mode symbol must contain exactly one character")

			symbolStorage = newValue
		}
	}

	@objc override public var modeParameter: String? {
		get { parameterStorage }
		set { parameterStorage = newValue }
	}

	override public func copy(with _: NSZone? = nil) -> Any {
		ModeInfo(copying: self)
	}
}
