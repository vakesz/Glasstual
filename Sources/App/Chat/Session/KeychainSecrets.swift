// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerConfig {
	var pendingKeychainEdits: KeychainPersistence.Edits {
		var edits: KeychainPersistence.Edits = [
			nicknamePasswordKeychainItem: pendingNicknamePassword,
			proxyPasswordKeychainItem: pendingProxyPassword,
		]
		for server in serverList {
			edits[server.keychainItem] = server.pendingServerPassword
		}
		for conversation in conversationList {
			edits[conversation.keychainItem] = conversation.pendingSecretKey
		}
		return edits.filter { $0.value != .unchanged }
	}

	var keychainItems: [KeychainItem] {
		[nicknamePasswordKeychainItem, proxyPasswordKeychainItem]
			+ serverList.map(\.keychainItem) + conversationList.map(\.keychainItem)
	}

	mutating func acknowledgeKeychainEdits(_ edits: KeychainPersistence.Edits) {
		if edits[nicknamePasswordKeychainItem] == pendingNicknamePassword {
			pendingNicknamePassword = .unchanged
		}
		if edits[proxyPasswordKeychainItem] == pendingProxyPassword {
			pendingProxyPassword = .unchanged
		}
		for index in serverList.indices where edits[serverList[index].keychainItem] == serverList[index].pendingServerPassword {
			serverList[index].pendingServerPassword = .unchanged
		}
		for index in conversationList.indices {
			conversationList[index].acknowledgeKeychainEdits(edits)
		}
	}
}

extension ConversationConfig {
	var pendingKeychainEdits: KeychainPersistence.Edits {
		pendingSecretKey == .unchanged ? [:] : [keychainItem: pendingSecretKey]
	}

	mutating func acknowledgeKeychainEdits(_ edits: KeychainPersistence.Edits) {
		if edits[keychainItem] == pendingSecretKey {
			pendingSecretKey = .unchanged
		}
	}
}

/** Reads keychain secrets away from the main actor.

 Every `KeychainItem.password` is a synchronous `SecItemCopyMatching`.
 Connections and editors request their secrets together, off the main actor,
 and own the resulting snapshot for their session. */
nonisolated enum KeychainSecretLoader {
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
	static func duplicate(_ config: ServerConfig) async -> ServerConfig {
		config.uniqueCopy()
	}
}
