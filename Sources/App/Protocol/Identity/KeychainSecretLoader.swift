/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

/** Reads keychain secrets away from the main actor.

 Every `KeychainItem.password` is a synchronous `SecItemCopyMatching`.
 Connections and editors request their secrets together, off the main actor,
 and own the resulting snapshot for their session. */
nonisolated enum KeychainSecretLoader { // nonisolated: value
	@concurrent
	static func passwords(for items: [KeychainItem]) async -> [KeychainItem: String] {
		var passwords: [KeychainItem: String] = [:]

		for item in Set(items) {
			if Task.isCancelled {
				break
			}
			if let password = item.password {
				passwords[item] = password
			}
		}

		return passwords
	}

	@concurrent
	static func duplicate(_ config: ClientConfig) async -> ClientConfig {
		config.uniqueCopy()
	}
}
