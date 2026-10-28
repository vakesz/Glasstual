// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// The last authenticated persistence offer on one live connection. Its duration
/// starts again when that connection closes, even if the cached expiry elapsed.
struct STSConnectionPolicy {
	let host: String
	let port: UInt16
	let values: STSCapabilityValues
}

/// The STS policies this session has been told to honour, keyed by host.
///
/// Main-actor, like the connection setup and the capability negotiation that
/// are its only callers, so the policies need no lock of their own.
final class STSPolicyStore {
	private let userDefaults: UserDefaults?
	private var policies: [String: STSPolicy] = [:]
	/// Plaintext upgrades that failed, to avoid looping against a dead TLS port.
	private var failedUpgrades: [String: (port: UInt16, date: Date)] = [:]
	/// How long a failed upgrade suppresses another to the same endpoint.
	static let failedUpgradeCooldown: TimeInterval = 5 * 60

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

	func applyCapabilityValues(
		_ values: STSCapabilityValues,
		forHost host: String,
		connectedPort: UInt16,
		secured: Bool,
		certificateChainValidated: Bool
	) -> STSPolicyAction {
		if secured == false {
			// An explicit `duration=0` withdraws the policy and never upgrades.
			// A port-only offer without a duration still upgrades, as before.
			if values.hasDuration, values.duration <= 0 {
				return .none
			}
			guard values.port > 0 else {
				return .none
			}

			if upgradeRecentlyFailed(host: host, port: values.port) {
				return .none
			}

			return .upgrade(port: values.port)
		}

		/* IRCv3 requires a policy offered over a connection whose certificate
		 did not validate to be ignored. Otherwise anyone who can present a
		 certificate the user clicks through once gets to pin the host. */
		guard certificateChainValidated, values.hasDuration else {
			return .none
		}

		if values.duration <= 0 {
			removePolicy(forHost: host)

			return .cleared
		}

		// The upgrade port is meaningful only on an insecure connection.
		let policyPort = connectedPort

		guard policyPort > 0 else {
			return .none
		}

		let policy = STSPolicy(
			port: policyPort,
			expiresAt: Date(timeIntervalSinceNow: values.duration),
			preload: values.preload
		)

		setPolicy(policy, forHost: host)

		return .stored(port: policyPort)
	}

	/// Records that a plaintext-to-TLS upgrade to `port` failed, so the next
	/// offer within the cooldown stays on plaintext instead of looping.
	func noteUpgradeFailed(host: String, port: UInt16) {
		failedUpgrades[key(forHost: host)] = (port, Date())
	}

	/// Clears the failure record, e.g. after a successful TLS connection.
	func noteUpgradeSucceeded(host: String) {
		failedUpgrades.removeValue(forKey: key(forHost: host))
	}

	private func upgradeRecentlyFailed(host: String, port: UInt16) -> Bool {
		guard let record = failedUpgrades[key(forHost: host)], record.port == port else {
			return false
		}
		if Date().timeIntervalSince(record.date) > Self.failedUpgradeCooldown {
			failedUpgrades.removeValue(forKey: key(forHost: host))
			return false
		}
		return true
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
