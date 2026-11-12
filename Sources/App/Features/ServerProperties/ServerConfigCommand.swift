// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// How a configuration setting's value is typed.
nonisolated enum ConfigurationValueKind: Equatable, Sendable {
	case flag
	case text
	case number(ClosedRange<Int>)
	case choice([String])
	/// A secret, asked for in a secure field and never typed on a command line.
	case secret
	/// A list edited with `add`, `remove` and `clear`.
	case list

	/// A flag typed as a word.
	static func flagValue(_ text: String) -> Bool? {
		switch text.lowercased() {
		case "on", "yes", "true", "1", "enable", "enabled": true
		case "off", "no", "false", "0", "disable", "disabled": false
		default: nil
		}
	}

	/// What the kind accepts, for a refusal to quote.
	var accepted: String {
		switch self {
		case .flag: "on | off"
		case .text: "text"
		case let .number(range): "\(range.lowerBound)…\(range.upperBound)"
		case let .choice(choices): choices.joined(separator: " | ")
		case .secret: ""
		case .list: "list | add <value> | remove <number> | clear"
		}
	}
}

/** One `/serverconfig` setting: a control of the Server Properties sheet,
 reached through the sheet's own model.

 Writing goes through the same model fields the sheet's controls bind to, and
 the sheet's validation decides whether the result can be saved, so the
 command and the sheet accept exactly the same values. */
@MainActor
struct ServerConfigField {
	let name: String
	let kind: ConfigurationValueKind
	let read: (ServerPropertiesModel) -> String
	/// Sets the field, or answers `false` for a value it cannot hold.
	let write: (ServerPropertiesModel, String) -> Bool

	static func flag(_ name: String, _ keyPath: WritableKeyPath<ServerConfig, Bool>) -> Self {
		Self(name: name, kind: .flag) { model in
			model.config[keyPath: keyPath] ? "on" : "off"
		} write: { model, text in
			guard let value = ConfigurationValueKind.flagValue(text) else { return false }
			model.config[keyPath: keyPath] = value
			return true
		}
	}

	static func text(_ name: String, _ keyPath: WritableKeyPath<ServerConfig, String>) -> Self {
		Self(name: name, kind: .text) { $0.config[keyPath: keyPath] } write: { model, text in
			model.config[keyPath: keyPath] = text
			return true
		}
	}

	static func optionalText(_ name: String, _ keyPath: WritableKeyPath<ServerConfig, String?>) -> Self {
		Self(name: name, kind: .text) { $0.config[keyPath: keyPath] ?? "" } write: { model, text in
			model.config[keyPath: keyPath] = text.isEmpty ? nil : text
			return true
		}
	}

	static func modelText(_ name: String, _ keyPath: ReferenceWritableKeyPath<ServerPropertiesModel, String>) -> Self {
		Self(name: name, kind: .text) { $0[keyPath: keyPath] } write: { model, text in
			model[keyPath: keyPath] = text
			return true
		}
	}

	static func secret(_ name: String, _ field: ServerPropertiesModel.SecretField) -> Self {
		Self(name: name, kind: .secret) { _ in "" } write: { model, text in
			model.setSecretText(text, for: field)
			return true
		}
	}

	static func choice<Value: Equatable>(
		_ name: String,
		_ choices: [(String, Value)],
		get: @escaping (ServerPropertiesModel) -> Value,
		set: @escaping (ServerPropertiesModel, Value) -> Void
	) -> Self {
		Self(name: name, kind: .choice(choices.map(\.0))) { model in
			let value = get(model)
			return choices.first { $0.1 == value }?.0 ?? ""
		} write: { model, text in
			guard let value = choices.first(where: { $0.0 == text.lowercased() })?.1 else { return false }
			set(model, value)
			return true
		}
	}

	static func number(
		_ name: String,
		_ range: ClosedRange<Int>,
		get: @escaping (ServerConfig) -> Int,
		set: @escaping (inout ServerConfig, Int) -> Void
	) -> Self {
		Self(name: name, kind: .number(range)) { String(get($0.config)) } write: { model, text in
			guard let value = Int(text), range.contains(value) else { return false }
			set(&model.config, value)
			return true
		}
	}

	static func list(
		_ name: String,
		get: @escaping (ServerPropertiesModel) -> [String],
		set: @escaping (ServerPropertiesModel, [String]) -> Void
	) -> Self {
		Self(name: name, kind: .list) { get($0).joined(separator: ", ") } write: { model, text in
			var items = get(model)
			var words = text.split(separator: " ", maxSplits: 1).map(String.init)
			guard words.isEmpty == false else { return false }
			let action = words.removeFirst().lowercased()
			let argument = words.first?.trimmingCharacters(in: .whitespaces) ?? ""
			switch action {
			case "add" where argument.isEmpty == false:
				items.append(argument)
			case "remove":
				guard let number = Int(argument), items.indices.contains(number - 1) else { return false }
				items.remove(at: number - 1)
			case "clear" where argument.isEmpty:
				items.removeAll()
			default:
				return false
			}
			set(model, items)
			return true
		}
	}
}

extension ServerConfigField {
	/** Every setting of the Server Properties sheet that a line of text can
	 hold. Choosing a client certificate or importing a signing key opens a
	 system panel, so those stay the sheet's; the command can clear them. */
	static let all: [ServerConfigField] = general + identity + authentication + network + behavior + bouncer + messages

	static func named(_ name: String) -> ServerConfigField? {
		all.first { $0.name == name.lowercased() }
	}

	/** Whether `reset` can return the setting to what a new server has.

	 Where the server is and how it is reached have no such value: an empty
	 configuration has no address, and resetting TLS would turn it off. Those
	 are set, never reset. */
	var isResettable: Bool {
		Self.endpointFields.contains(name) == false
	}

	private static let endpointFields: Set<String> = ["address", "port", "tls", "transport", "websocket-path", "servers"]

	private static let general: [ServerConfigField] = [
		.text("name", \.connectionName),
		.modelText("address", \.serverAddress),
		.modelText("port", \.serverPort),
		Self(name: "tls", kind: .flag) { $0.primaryServerIsSecured ? "on" : "off" } write: { model, text in
			guard let value = ConfigurationValueKind.flagValue(text) else { return false }
			model.setPrimaryServerSecured(value)
			return true
		},
		.choice("transport", [("irc", ServerTransport.irc), ("websocket", .webSocket)]) {
			$0.primaryServerTransport
		} set: { $0.primaryServerTransport = $1 },
		Self(name: "websocket-path", kind: .text) { $0.primaryWebSocketPath } write: { model, text in
			model.primaryWebSocketPath = text
			return true
		},
		.secret("server-password", .serverPassword),
		.list("servers") { model in
			model.config.serverList.map { endpoint in
				"\(endpoint.serverAddress) \(endpoint.prefersSecuredConnection ? "+" : "")\(endpoint.serverPort)"
			}
		} set: { model, items in
			let existing = model.config.serverList
			let servers: [ServerEndpoint] = items.compactMap { item in
				if let match = existing.first(where: {
					item == "\($0.serverAddress) \($0.prefersSecuredConnection ? "+" : "")\($0.serverPort)"
				}) {
					return match
				}
				var words = item.split(separator: " ").map(String.init)
				guard words.isEmpty == false else { return nil }
				let address = words.removeFirst()
				let portWord = words.first ?? "6697"
				let secured = portWord.hasPrefix("+") || words.isEmpty
				let port = UInt16(portWord.trimmingCharacters(in: CharacterSet(charactersIn: "+"))) ?? 6697
				return ServerEndpoint(serverAddress: address, serverPort: port, prefersSecuredConnection: secured)
			}
			model.applyServerList(servers)
		},
		.flag("autoconnect", \.autoConnect),
		.flag("autoreconnect", \.autoReconnect),
		.flag("validate-certificate", \.validateServerCertificateChain),
		.choice("cipher-suites", [
			("system", CipherSuiteCollection.system), ("modern", .modern), ("intermediate", .intermediate),
		]) { $0.config.cipherSuites } set: { $0.config.cipherSuites = $1 },
	]

	private static let identity: [ServerConfigField] = [
		.text("nickname", \.nickname),
		.optionalText("away-nickname", \.awayNickname),
		.modelText("alternate-nicknames", \.alternateNicknames),
		.text("username", \.username),
		.text("realname", \.realName),
		.secret("nickname-password", .nicknamePassword),
	]

	private static let authentication: [ServerConfigField] = [
		.flag("sasl", \.usesSASL),
		.choice(
			"sasl-mechanism",
			[("automatic", SASLMechanism?.none)] + SASLMechanism.defaultOrder.map { ($0.wireName.lowercased(), Optional($0)) }
		) { $0.config.saslMechanismPreference } set: { $0.config.saslMechanismPreference = $1 },
		.flag("sasl-only-mechanism", \.saslUsesOnlyPreferredMechanism),
		.flag("sasl-reauthenticate", \.saslReauthenticatesAutomatically),
		.flag("sasl-disconnect-on-failure", \.disconnectOnSASLFailure),
		.flag("sasl-external-disabled", \.saslAuthenticationDisableExternalMechanism),
		.flag("userserv", \.sendAuthenticationRequestsToUserServ),
		.secret("sasl-token", .saslBearerToken),
		Self(name: "client-certificate", kind: .choice(["clear"])) {
			$0.config.identityClientSideCertificate == nil ? "" : "set"
		} write: { model, text in
			guard text.lowercased() == "clear" else { return false }
			model.config.identityClientSideCertificate = nil
			return true
		},
		Self(name: "signing-key", kind: .choice(["generate", "remove"])) { _ in "" } write: { model, text in
			switch text.lowercased() {
			case "generate": model.generateSigningKey()
			case "remove": model.removeSigningKey()
			default: return false
			}
			return true
		},
	]

	private static let network: [ServerConfigField] = [
		.choice("address-type", [
			("any", ConnectionAddressKind.default), ("ipv4", .v4), ("ipv6", .v6),
		]) { $0.config.addressType } set: { $0.config.addressType = $1 },
		.flag("prefer-ipv4", \.connectionPrefersIPv4),
		.choice("proxy", [
			("automatic", ConnectionProxyKind.automatic), ("none", .none), ("socks5", .socks5), ("http", .HTTP), ("tor", .tor),
		]) { $0.config.proxyType } set: { $0.config.proxyType = $1 },
		.modelText("proxy-address", \.proxyAddress),
		.modelText("proxy-port", \.proxyPort),
		.modelText("proxy-username", \.proxyUsername),
		.secret("proxy-password", .proxyPassword),
		Self(name: "encoding", kind: .text) { encodingName($0.config.primaryEncoding) } write: { model, text in
			guard let encoding = encoding(named: text) else { return false }
			model.config.primaryEncoding = encoding
			return true
		},
		Self(name: "fallback-encoding", kind: .text) { encodingName($0.config.fallbackEncoding) } write: { model, text in
			guard let encoding = encoding(named: text) else { return false }
			model.config.fallbackEncoding = encoding
			return true
		},
		.number("flood-delay", 0 ... 60) { Int($0.floodControlDelayTimerInterval) } set: {
			$0.floodControlDelayTimerInterval = .init($1)
		},
		.number("flood-maximum", 1 ... 100) { Int($0.floodControlMaximumMessages) } set: {
			$0.floodControlMaximumMessages = .init($1)
		},
	]

	private static let behavior: [ServerConfigField] = [
		.flag("sleep-disconnect", \.autoSleepModeDisconnect),
		.flag("reachability-disconnect", \.performDisconnectOnReachabilityChange),
		.flag("pong-timer", \.performPongTimer),
		.flag("pong-timer-disconnect", \.performDisconnectOnPongTimer),
		.flag("autojoin-waits-for-nickserv", \.autojoinWaitsForNickServ),
		.flag("autojoin-waits-for-connect-commands", \.autojoinWaitsForConnectCommands),
		.number("autojoin-delay", 0 ... 300) { Int($0.autojoinDelayAfterConnectCommands) } set: {
			$0.autojoinDelayAfterConnectCommands = .init($1)
		},
		.flag("hide-autojoin-warnings", \.hideAutojoinDelayedWarnings),
		.flag("hide-network-notices", \.hideNetworkUnavailabilityNotices),
		.flag("who-requests", \.sendWhoCommandRequestsToChannels),
		.flag("invisible", \.setInvisibleModeOnConnect),
		.flag("connect-commands-silent", \.runConnectCommandsSilently),
		.list("connect-commands") { model in
			model.connectCommands.components(separatedBy: .newlines).filter { $0.isEmpty == false }
		} set: { model, items in
			model.connectCommands = items.joined(separator: "\n")
		},
		.list("highlights") { model in
			model.config.highlightList.map { ($0.matchIsExcluded ? "-" : "") + $0.matchKeyword }
		} set: { model, items in
			let existing = model.config.highlightList
			model.config.highlightList = items.map { item in
				if let match = existing.first(where: { ($0.matchIsExcluded ? "-" : "") + $0.matchKeyword == item }) {
					return match
				}
				let excluded = item.hasPrefix("-")
				return HighlightMatchCondition(
					matchKeyword: excluded ? String(item.dropFirst()) : item, matchChannelId: nil, matchIsExcluded: excluded
				)
			}
		},
	]

	private static let bouncer: [ServerConfigField] = [
		.flag("znc-ignore-autojoin", \.zncIgnoreConfiguredAutojoin),
		.flag("znc-ignore-playback-notifications", \.zncIgnorePlaybackNotifications),
		.flag("znc-ignore-user-notifications", \.zncIgnoreUserNotifications),
		.flag("znc-only-latest-playback", \.zncOnlyPlaybackLatest),
		.flag("bouncer-discovers-networks", \.bouncerDiscoversNetworks),
		.flag("bouncer-hides-parent", \.bouncerHidesParent),
	]

	private static let messages: [ServerConfigField] = [
		.text("quit-message", \.normalLeavingComment),
		.text("sleep-quit-message", \.sleepModeLeavingComment),
		.optionalText("ctcp-version", \.ctcpVersionReply),
	]

	/// An encoding's IANA name, as `/serverconfig encoding utf-8` takes it.
	static func encodingName(_ rawValue: UInt) -> String {
		let encoding = CFStringConvertNSStringEncodingToEncoding(rawValue)
		return (CFStringConvertEncodingToIANACharSetName(encoding) as String?)?.lowercased() ?? String(rawValue)
	}

	static func encoding(named name: String) -> UInt? {
		let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
		guard encoding != kCFStringEncodingInvalidId else { return nil }
		return CFStringConvertEncodingToNSStringEncoding(encoding)
	}
}
