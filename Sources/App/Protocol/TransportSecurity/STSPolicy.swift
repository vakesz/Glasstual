// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// What a server's STS offer amounted to.
///
/// The port used to leave through an out-parameter the caller had to know to
/// read, and only for one of the four outcomes; it rides on the case that
/// carries it instead.
nonisolated enum STSPolicyAction: Sendable, Equatable {
	/// Nothing to do: no offer, or one that has to be ignored.
	case none

	/// The connection should be reopened, secured, on this port.
	case upgrade(port: UInt16)

	/// A policy with this scope was stored.
	case stored(STSPolicyScope)

	/// The host's stored policy was withdrawn.
	case cleared
}

/// What a stored policy pins.
///
/// A policy learned over IRC names the TLS IRC port the server proved it serves.
/// One learned over a WebSocket only proves TLS: the port it arrived on is an
/// HTTPS port, so every entry for the host keeps its own port and gains TLS.
nonisolated enum STSPolicyScope: Sendable, Equatable {
	/// TLS IRC on this port.
	case port(UInt16)
	/// TLS on each entry's own port and transport.
	case host
}

nonisolated struct STSPolicy: Sendable, Equatable {
	let scope: STSPolicyScope
	let expiresAt: Date
	let preload: Bool

	init(scope: STSPolicyScope, expiresAt: Date, preload: Bool) {
		if case let .port(port) = scope {
			precondition(port > 0)
		}

		self.scope = scope
		self.expiresAt = expiresAt
		self.preload = preload
	}

	init(port: UInt16, expiresAt: Date, preload: Bool) {
		self.init(scope: .port(port), expiresAt: expiresAt, preload: preload)
	}

	var isExpired: Bool {
		expiresAt.timeIntervalSinceNow <= 0
	}

	/// Entries without a `scope` predate host-only policies and pin `port`.
	init?(dictionary: [String: PropertyListValue]) {
		guard let expiresAt = dictionary[StorageKey.expiresAt]?.double else {
			return nil
		}

		let scope: STSPolicyScope
		if dictionary[StorageKey.scope]?.string == StorageKey.hostScope {
			scope = .host
		} else {
			guard let port = dictionary[StorageKey.port]?.integer, port > 0, port <= UInt16.max else {
				return nil
			}
			scope = .port(UInt16(port))
		}

		self.init(
			scope: scope,
			expiresAt: Date(timeIntervalSince1970: expiresAt),
			preload: dictionary[StorageKey.preload]?.boolean ?? false
		)
	}

	/// A host-only policy writes no `port`, so a build that predates it drops
	/// the entry instead of pinning the host to a WebSocket port.
	var dictionaryValue: [String: PropertyListValue] {
		var dictionary: [String: PropertyListValue] = [
			StorageKey.expiresAt: .double(expiresAt.timeIntervalSince1970),
			StorageKey.preload: .boolean(preload),
		]
		switch scope {
		case let .port(port):
			dictionary[StorageKey.port] = .integer(Int(port))
		case .host:
			dictionary[StorageKey.scope] = .string(StorageKey.hostScope)
		}
		return dictionary
	}

	private enum StorageKey {
		static let port = "port"
		static let expiresAt = "expiresAt"
		static let preload = "preload"
		static let scope = "scope"
		static let hostScope = "host"
	}
}

/** The `sts` capability's parsed key/value list.

 Capability negotiation parses the offer; an authenticated connection retains
 its last persistence offer to renew the policy when it closes. */
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
					// The wire integer has no upper bound. Keep an overflowing
					// offer enforceable without persisting a non-finite expiry.
					result.duration = min(duration, .greatestFiniteMagnitude)
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
