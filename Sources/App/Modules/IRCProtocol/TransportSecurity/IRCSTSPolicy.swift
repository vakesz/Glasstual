/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

public typealias IRCSTSCapabilityValues = STSCapabilityValues
public typealias IRCSTSPolicy = STSPolicy

@objc public enum IRCSTSPolicyAction: UInt {
	case none
	case upgrade
	case stored
	case cleared
}

@objc(IRCSTSPolicy)
public final class STSPolicy: NSObject {
	@objc public let port: UInt16
	@objc public let expiresAt: Date
	@objc public let preload: Bool

	@objc(initWithPort:expiresAt:preload:)
	public init(port: UInt16, expiresAt: Date, preload: Bool) {
		precondition(port > 0)

		self.port = port
		self.expiresAt = expiresAt
		self.preload = preload

		super.init()
	}

	@objc public var isExpired: Bool {
		expiresAt.timeIntervalSinceNow <= 0
	}

	override public var description: String {
		"<\(NSStringFromClass(type(of: self))) port=\(port) expiresAt=\(expiresAt)>"
	}

	convenience init?(dictionary: [String: Any]) {
		guard
			let port = dictionary[StorageKey.port] as? NSNumber,
			let expiresAt = dictionary[StorageKey.expiresAt] as? NSNumber,
			port.intValue > 0,
			port.intValue <= UInt16.max
		else {
			return nil
		}

		self.init(
			port: port.uint16Value,
			expiresAt: Date(timeIntervalSince1970: expiresAt.doubleValue),
			preload: Self.boolValue(dictionary[StorageKey.preload])
		)
	}

	var dictionaryValue: [String: Any] {
		[
			StorageKey.port: NSNumber(value: port),
			StorageKey.expiresAt: NSNumber(value: expiresAt.timeIntervalSince1970),
			StorageKey.preload: NSNumber(value: preload),
		]
	}

	private enum StorageKey {
		static let port = "port"
		static let expiresAt = "expiresAt"
		static let preload = "preload"
	}

	private static func boolValue(_ value: Any?) -> Bool {
		if let number = value as? NSNumber {
			return number.boolValue
		}

		if let string = value as? NSString {
			return string.boolValue
		}

		return false
	}
}
