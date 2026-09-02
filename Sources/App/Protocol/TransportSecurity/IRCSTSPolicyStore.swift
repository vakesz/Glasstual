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

public typealias IRCSTSPolicyStore = STSPolicyStore

public let IRCSTSPolicyStoreDefaultsKey = Preferences.Connection.stsPolicies.name

/// The STS policies this client has been told to honour, keyed by host.
///
/// Main-actor, like the connection setup and the capability negotiation that
/// are its only callers, so the policies need no lock of their own.
public final class STSPolicyStore: NSObject {
	private let userDefaults: UserDefaults?
	private var policies: [String: STSPolicy] = [:]

	public static let shared = STSPolicyStore(userDefaults: TextualUserDefaults.container)

	public init(userDefaults: UserDefaults?) {
		self.userDefaults = userDefaults

		super.init()

		load()
	}

	public func policy(forHost host: String) -> STSPolicy? {
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

	public func setPolicy(_ policy: STSPolicy, forHost host: String) {
		policies[key(forHost: host)] = policy
		save()
	}

	public func removePolicy(forHost host: String) {
		guard policies.removeValue(forKey: key(forHost: host)) != nil else {
			return
		}

		save()
	}

	/// The endpoint a stored policy pins `host` to, or `nil` when there is no
	/// policy. A stored policy always requires a secured connection, so the
	/// port is the whole answer.
	public func enforcedEndpoint(forHost host: String) -> STSPolicyEndpoint? {
		guard let policy = policy(forHost: host) else {
			return nil
		}

		return STSPolicyEndpoint(port: policy.port)
	}

	/// The longest an advertised policy is allowed to last.
	///
	/// `duration` is otherwise unbounded, so a server that once spoke for a
	/// host could pin it effectively forever.
	public static let maximumPolicyDuration: TimeInterval = 365 * 24 * 60 * 60

	public func applyCapabilityValues(
		_ values: STSCapabilityValues,
		forHost host: String,
		connectedPort: UInt16,
		secured: Bool,
		certificateChainValidated: Bool
	) -> IRCSTSPolicyAction {
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

	private func key(forHost host: String) -> String {
		host.lowercased()
	}

	private func load() {
		guard let stored = userDefaults?.dictionary(forKey: IRCSTSPolicyStoreDefaultsKey) else {
			return
		}

		for (host, value) in stored {
			guard
				let dictionary = [String: PropertyListValue](propertyList: value),
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

		let stored = policies.mapValues { $0.dictionaryValue.propertyListObject }

		userDefaults.set(stored, forKey: IRCSTSPolicyStoreDefaultsKey)
	}
}
