// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** One upstream network a soju account owns, as `BOUNCER NETWORK` describes it.

 The grammar is soju's `soju.im/bouncer-networks` extension. A network is
 named by an opaque identifier the bouncer assigns and described by a set of
 attributes. Only the attributes Glasstual shows or edits are kept; the rest are
 ignored so a bouncer that adds one does not break the listing. */
nonisolated struct BouncerNetwork: Sendable, Equatable, Identifiable {
	/// What the bouncer says the upstream connection is doing.
	enum State: String, Sendable, Equatable {
		case connected
		case connecting
		case disconnected
	}

	let id: String
	var name: String?
	var state: State?
	/// The reason the upstream connection last failed, in the bouncer's words.
	var error: String?
	var host: String?
	var port: UInt16?
	var usesTLS: Bool?
	var nickname: String?
	var username: String?
	var realName: String?

	/// The name the sidebar shows: the one the user chose, or the best
	/// stand-in the bouncer gave.
	var displayName: String {
		name?.nonEmpty ?? host?.nonEmpty ?? id
	}

	/// A network from the identifier and attributes of one `BOUNCER NETWORK`
	/// line, or `nil` when either breaks the extension's grammar or its limits.
	init?(id: String, attributeText: String) {
		guard BouncerNetworkAttributes.isValidNetworkIdentifier(id),
		      let attributes = BouncerNetworkAttributes.parse(attributeText)
		else { return nil }

		self.id = id
		apply(attributes)
	}

	/** Lays the attributes of an update over this network.

	 An update names only what changed. An attribute present with a value
	 replaces it, one present with an empty value is removed, and one that is
	 absent is left alone. */
	mutating func apply(_ attributes: [String: String]) {
		for (key, value) in attributes {
			let text = value.nonEmpty
			switch key {
			case "name": name = text
			case "state": state = text.flatMap(State.init(rawValue:))
			case "error": error = text
			case "host": host = text
			case "port": port = text.flatMap(UInt16.init)
			case "tls": usesTLS = text.map { $0 == "1" }
			case "nickname": nickname = text
			case "username": username = text
			case "realname": realName = text
			default: break
			}
		}
	}

	init(id: String, name: String? = nil, state: State? = nil) {
		self.id = id
		self.name = name
		self.state = state
	}
}

/** What a user asks the bouncer to store for a network.

 Fields left `nil` are not sent, so `CHANGENETWORK` leaves them alone. */
nonisolated struct BouncerNetworkEdit: Sendable, Equatable {
	var name: String?
	var host: String?
	var port: UInt16?
	var usesTLS: Bool?
	var nickname: String?
	var username: String?
	var realName: String?
	var password: String?

	/// The attribute list for `ADDNETWORK` or `CHANGENETWORK`, in a stable order.
	var attributeText: String {
		var pairs: [(String, String)] = []
		if let name {
			pairs.append(("name", name))
		}
		if let host {
			pairs.append(("host", host))
		}
		if let port {
			pairs.append(("port", String(port)))
		}
		if let usesTLS {
			pairs.append(("tls", usesTLS ? "1" : "0"))
		}
		if let nickname {
			pairs.append(("nickname", nickname))
		}
		if let username {
			pairs.append(("username", username))
		}
		if let realName {
			pairs.append(("realname", realName))
		}
		if let password {
			pairs.append(("pass", password))
		}
		return BouncerNetworkAttributes.serialize(pairs)
	}
}

/** The attribute grammar and the limits that keep a hostile bouncer bounded. */
nonisolated enum BouncerNetworkAttributes {
	/// Networks one bouncer connection may define. Later ones are dropped.
	static let maximumNetworks = 64
	static let maximumNetworkIdentifierLength = 64
	static let maximumAttributes = 32
	static let maximumKeyBytes = 64
	static let maximumValueBytes = 512

	/// A network identifier is a short token. `*` is excluded because it is the
	/// marker a deletion is announced with.
	static func isValidNetworkIdentifier(_ identifier: String) -> Bool {
		guard identifier.isEmpty == false, identifier.utf8.count <= maximumNetworkIdentifierLength else {
			return false
		}
		return identifier.unicodeScalars.allSatisfy { scalar in
			scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar))
		}
	}

	/// The decoded attributes of one list, or `nil` when it exceeds a limit.
	static func parse(_ text: String) -> [String: String]? {
		guard text.utf8.count <= maximumAttributes * (maximumKeyBytes + maximumValueBytes + 2) else { return nil }
		let section = MessageTagParser.parsedTags(fromSection: text).tags
		guard section.count <= maximumAttributes else { return nil }
		for (key, value) in section where key.utf8.count > maximumKeyBytes || value.utf8.count > maximumValueBytes {
			return nil
		}
		return section
	}

	/// An attribute list as it travels: `key=value` pairs joined by `;`, with
	/// the message-tag escapes, so it is a single wire parameter.
	static func serialize(_ pairs: [(String, String)]) -> String {
		pairs.map { "\($0.0)=\(escape($0.1))" }.joined(separator: ";")
	}

	private static func escape(_ value: String) -> String {
		value
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: ";", with: "\\:")
			.replacingOccurrences(of: " ", with: "\\s")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\n", with: "\\n")
	}
}
