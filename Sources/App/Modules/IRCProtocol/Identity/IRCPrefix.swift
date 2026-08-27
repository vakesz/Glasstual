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

@objc(IRCPrefix)
public class Prefix: PortablePropertyObject {
	fileprivate var serverStorage = false
	fileprivate var hostmaskStorage = ""
	fileprivate var nicknameStorage = ""
	fileprivate var usernameStorage: String?
	fileprivate var addressStorage: String?

	@objc public var isServer: Bool {
		serverStorage
	}

	@objc public var hostmask: String {
		hostmaskStorage
	}

	@objc public var nickname: String {
		nicknameStorage
	}

	@objc public var username: String? {
		usernameStorage
	}

	@objc public var address: String? {
		addressStorage
	}

	override public init() {
		super.init()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override public func copy(with _: NSZone? = nil) -> Any {
		if type(of: self) == Prefix.self {
			return self
		}

		return Prefix(copying: self)
	}

	override public func mutableCopy(with _: NSZone? = nil) -> Any {
		MutablePrefix(copying: self)
	}

	override public func copy(asMutable mutableCopy: Bool) -> Any {
		copy(asMutable: mutableCopy, uniquing: false)
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing _: Bool) -> Any {
		mutableCopy ? MutablePrefix(copying: self) : Prefix(copying: self)
	}

	override public func uniqueCopy(asMutable mutableCopy: Bool) -> Any {
		copy(asMutable: mutableCopy, uniquing: true)
	}

	override public func uniqueCopy() -> Any {
		Prefix(copying: self)
	}

	override public func uniqueCopyMutable() -> Any {
		MutablePrefix(copying: self)
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? Prefix else {
			return false
		}

		return isServer == other.isServer && nickname == other.nickname && username == other.username
			&& address == other.address && hostmask == other.hostmask
	}

	override public var hash: Int {
		var hasher = Hasher()
		hasher.combine(isServer)
		hasher.combine(nickname)
		hasher.combine(username)
		hasher.combine(address)
		hasher.combine(hostmask)

		return hasher.finalize()
	}

	fileprivate convenience init(copying prefix: Prefix) {
		self.init()

		serverStorage = prefix.isServer
		hostmaskStorage = prefix.hostmask
		nicknameStorage = prefix.nickname
		usernameStorage = prefix.username
		addressStorage = prefix.address
	}
}

@objc(IRCPrefixMutable)
public final class MutablePrefix: Prefix {
	override public static var isMutable: Bool {
		true
	}

	@objc override public var isServer: Bool {
		get { serverStorage }
		set { serverStorage = newValue }
	}

	@objc override public var hostmask: String {
		get { hostmaskStorage }
		set { hostmaskStorage = newValue }
	}

	@objc override public var nickname: String {
		get { nicknameStorage }
		set { nicknameStorage = newValue }
	}

	@objc override public var username: String? {
		get { usernameStorage }
		set { usernameStorage = newValue }
	}

	@objc override public var address: String? {
		get { addressStorage }
		set { addressStorage = newValue }
	}

	override public func copy(with _: NSZone? = nil) -> Any {
		Prefix(copying: self)
	}
}
