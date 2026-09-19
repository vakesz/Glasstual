// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// The STS policies this session has been told to honour, keyed by host.
///
/// Main-actor, like the connection setup and the capability negotiation that
/// are its only callers, so the policies need no lock of their own.
final class STSPolicyStore {
	private let userDefaults: UserDefaults?
	private var policies: [String: STSPolicy] = [:]

	/** The store the running application hands every session through its
	 services.

	 A policy names a host rather than a session, so one table serves every
	 connection. Sessions reach it through `ChatServices.stsPolicies`, never
	 statically, which is what lets a test drive the STS path with its own. */
	static let applicationStore = STSPolicyStore(userDefaults: GlasstualUserDefaults.container)

	init(userDefaults: UserDefaults?) {
		self.userDefaults = userDefaults

		load()
	}

	func policy(forHost host: String) -> STSPolicy? {
		let key = key(forHost: host)

		guard let policy = policies[key] else {
			return nil
		}

		if policy.isExpired {
			policies.removeValue(forKey: key)
			save()

			return nil
		}

		return policy
	}

	func setPolicy(_ policy: STSPolicy, forHost host: String) {
		policies[key(forHost: host)] = policy
		save()
	}

	func removePolicy(forHost host: String) {
		guard policies.removeValue(forKey: key(forHost: host)) != nil else {
			return
		}

		save()
	}

	/// The port a stored policy pins `host` to, or `nil` when there is no
	/// policy. A stored policy always requires a secured connection, so the
	/// port is the whole answer.
	func enforcedPort(forHost host: String) -> UInt16? {
		policy(forHost: host)?.port
	}

	/// The longest an advertised policy is allowed to last.
	///
	/// `duration` is otherwise unbounded, so a server that once spoke for a
	/// host could pin it effectively forever.
	static let maximumPolicyDuration: TimeInterval = 365 * 24 * 60 * 60

	func applyCapabilityValues(
		_ values: STSCapabilityValues,
		forHost host: String,
		connectedPort: UInt16,
		secured: Bool,
		certificateChainValidated: Bool
	) -> STSPolicyAction {
		if secured == false {
			guard values.port > 0 else {
				return .none
			}

			return .upgrade(port: values.port)
		}

		/* IRCv3 requires a policy offered over a connection whose certificate
		 did not validate to be ignored. Otherwise anyone who can present a
		 certificate the user clicks through once gets to pin the host. */
		guard certificateChainValidated else {
			return .none
		}

		guard values.hasDuration else {
			return .none
		}

		if values.duration <= 0 {
			removePolicy(forHost: host)

			return .cleared
		}

		let policyPort = values.port > 0 ? values.port : connectedPort

		guard policyPort > 0 else {
			return .none
		}

		let policy = STSPolicy(
			port: policyPort,
			expiresAt: Date(timeIntervalSinceNow: min(values.duration, Self.maximumPolicyDuration)),
			preload: values.preload
		)

		setPolicy(policy, forHost: host)

		return .stored(port: policyPort)
	}

	/** The key one host's policy is stored under.

	 A policy is about a name, not about a spelling of it. `irc.example.com.`
	 names the root-anchored form of `irc.example.com`, an IPv6 literal is
	 written both bare and bracketed depending on which end of the connection
	 wrote it, and DNS names are case-insensitive. Keying on the text as typed
	 filed those as separate hosts, so a policy stored under one spelling never
	 applied to the connection that used another. Case folding is invariant
	 rather than locale-sensitive: the Turkish locale maps `I` to a dotless
	 `ı`, which would key the same host differently for one user. */
	private func key(forHost host: String) -> String {
		var host = host

		while host.hasSuffix(".") {
			host.removeLast()
		}

		if host.hasPrefix("["), host.hasSuffix("]") {
			host = String(host.dropFirst().dropLast())
		}

		return host.lowercased(with: Locale(identifier: "en_US_POSIX"))
	}

	private func load() {
		guard let stored = userDefaults?.propertyListValue(for: SettingsKeys.Connection.stsPolicies)?.dictionary else {
			return
		}

		for (host, value) in stored {
			guard
				let dictionary = value.dictionary,
				let policy = STSPolicy(dictionary: dictionary),
				policy.isExpired == false
			else {
				continue
			}

			policies[key(forHost: host)] = policy
		}
	}

	private func save() {
		guard let userDefaults else {
			return
		}

		let stored = policies.mapValues { PropertyListValue.dictionary($0.dictionaryValue) }
		userDefaults.setPropertyListValue(.dictionary(stored), for: SettingsKeys.Connection.stsPolicies)
	}
}
