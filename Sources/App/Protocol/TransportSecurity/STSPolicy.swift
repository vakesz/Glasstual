/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import CocoaExtensions
import Foundation

/// What a server's STS offer amounted to.
///
/// The port used to leave through an out-parameter the caller had to know to
/// read, and only for one of the four outcomes; it rides on the case that
/// carries it instead.
nonisolated enum STSPolicyAction: Sendable, Equatable { // nonisolated: value
	/// Nothing to do: no offer, or one that has to be ignored.
	case none

	/// The connection should be reopened, secured, on this port.
	case upgrade(port: UInt16)

	/// A policy pinning the host to this port was stored.
	case stored(port: UInt16)

	/// The host's stored policy was withdrawn.
	case cleared
}

/// The endpoint a stored STS policy pins a host to.
nonisolated struct STSPolicyEndpoint: Sendable, Equatable { // nonisolated: value
	let port: UInt16
}

nonisolated struct STSPolicy: Sendable, Equatable { // nonisolated: value
	let port: UInt16
	let expiresAt: Date
	let preload: Bool

	init(port: UInt16, expiresAt: Date, preload: Bool) {
		precondition(port > 0)

		self.port = port
		self.expiresAt = expiresAt
		self.preload = preload
	}

	var isExpired: Bool {
		expiresAt.timeIntervalSinceNow <= 0
	}

	init?(dictionary: [String: PropertyListValue]) {
		guard
			let port = dictionary[StorageKey.port]?.integer,
			let expiresAt = dictionary[StorageKey.expiresAt]?.double,
			port > 0,
			port <= UInt16.max
		else {
			return nil
		}

		self.init(
			port: UInt16(port),
			expiresAt: Date(timeIntervalSince1970: expiresAt),
			preload: Self.boolValue(dictionary[StorageKey.preload])
		)
	}

	var dictionaryValue: [String: PropertyListValue] {
		[
			StorageKey.port: .integer(Int(port)),
			StorageKey.expiresAt: .double(expiresAt.timeIntervalSince1970),
			StorageKey.preload: .boolean(preload),
		]
	}

	private enum StorageKey {
		static let port = "port"
		static let expiresAt = "expiresAt"
		static let preload = "preload"
	}

	/// A policy written by an older build spells `preload` as the string the
	/// header carried, so a string still reads as the flag it stood for.
	private static func boolValue(_ value: PropertyListValue?) -> Bool {
		if let boolean = value?.boolean {
			return boolean
		}

		return (value?.string as NSString?)?.boolValue ?? false
	}
}

/** The `sts` capability's parsed key/value list.

 A value: capability negotiation parses one, the policy store reads it, and
 nothing keeps it past the negotiation that built it. */
struct STSCapabilityValues: Hashable, Sendable, CustomStringConvertible {
	private(set) var port: UInt16 = 0
	private(set) var hasDuration = false
	private(set) var duration: TimeInterval = 0
	private(set) var preload = false

	private init() {}

	static func values(fromCapabilityValues values: [String]) -> STSCapabilityValues? {
		var result = STSCapabilityValues()
		var recognizedKey = false

		for value in values {
			let (key, keyValue) = split(value: value)

			switch key.lowercased() {
			case "port":
				/* `UInt16(_:)` reports an out-of-range port by failing, where the
				 `NSString` conversion this replaced saturated at `Int.max`. */
				if isDecimalNumber(keyValue), let port = UInt16(keyValue), port > 0 {
					result.port = port
				}

				recognizedKey = true
			case "duration":
				if isDecimalNumber(keyValue), let duration = Double(keyValue) {
					result.hasDuration = true
					result.duration = duration
				}

				recognizedKey = true
			case "preload":
				result.preload = true
				recognizedKey = true
			default:
				break
			}
		}

		return recognizedKey ? result : nil
	}

	var description: String {
		"<STSCapabilityValues port=\(port) duration=\(String(format: "%.0f", duration)) preload=\(preload ? 1 : 0)>"
	}

	private static func split(value: String) -> (key: String, value: String) {
		guard let equalsIndex = value.firstIndex(of: "=") else {
			return (value, "")
		}

		return (
			String(value[..<equalsIndex]),
			String(value[value.index(after: equalsIndex)...])
		)
	}

	private static func isDecimalNumber(_ value: String) -> Bool {
		value.isEmpty == false && value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
	}
}
