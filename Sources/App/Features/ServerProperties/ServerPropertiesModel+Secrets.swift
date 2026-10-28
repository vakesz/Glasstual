// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerPropertiesModel {
	func loadSecrets() async {
		let passwords = await KeychainSecretLoader.passwords(for: secretKeychainItems)
		applyLoadedSecrets(passwords)
	}

	/** Describes the client certificate the connection sends, off the main
	 actor, and clears the description when it sends none.

	 The certificate is a persistent keychain reference, so naming it and
	 digesting it is a `SecItemCopyMatching` like the passwords: read as the
	 sheet opens, it was the stall between the click and the sheet. The view
	 runs this again whenever the reference changes, which cancels a read of
	 the previous one. */
	func loadCertificate() async {
		guard let reference = config.identityClientSideCertificate else {
			certificate = nil
			return
		}
		let details = await ClientCertificateLoader.certificate(for: reference)
		guard Task.isCancelled == false, reference == config.identityClientSideCertificate else { return }
		certificate = details
	}

	/// Whether the channel list shows a channel as having a key: an unflushed
	/// edit if there is one, and otherwise what the one keychain read found.
	func channelHasSecretKey(_ channel: ConversationConfig) -> Bool {
		channel.pendingSecretKey.value(orStored: loadedSecrets[channel.keychainItem])?.isEmpty == false
	}

	private var secretKeychainItems: [KeychainItem] {
		var items = [config.nicknamePasswordKeychainItem, config.proxyPasswordKeychainItem]

		if let primaryServer {
			items.append(primaryServer.keychainItem)
		}

		return items + displayedChannels.map(\.keychainItem)
	}

	private func applyLoadedSecrets(_ passwords: [KeychainItem: String]) {
		guard Task.isCancelled == false else { return }
		loadedSecrets = passwords

		/* A field the user has already typed into keeps what they typed — an
		 emptied one included, which is why this asks what was edited rather
		 than what is empty. */
		if editedSecretFields.contains(.serverPassword) == false {
			serverPasswordText = secret(
				primaryServer?.pendingServerPassword ?? .unchanged,
				from: primaryServer?.keychainItem
			)
		}
		if editedSecretFields.contains(.nicknamePassword) == false {
			nicknamePasswordText = secret(config.pendingNicknamePassword, from: config.nicknamePasswordKeychainItem)
		}
		if editedSecretFields.contains(.proxyPassword) == false {
			proxyPasswordText = secret(config.pendingProxyPassword, from: config.proxyPasswordKeychainItem)
		}
	}

	/// An unflushed edit if there is one, and otherwise what the one keychain
	/// read found. Never a keychain read of its own.
	func secret(_ pending: PendingKeychainSecret, from item: KeychainItem?) -> String {
		pending.value(orStored: item.flatMap { loadedSecrets[$0] }) ?? ""
	}

	/** What submitting one of the three fields asks the keychain to do.

	 Only a field the person typed into carries an instruction; every other one
	 hands back the edit the configuration already had, which is normally
	 `.unchanged`. Emitting `.edited(text)` for an untouched field wrote
	 `.cleared` for as long as the keychain read had not landed, which deleted
	 the secret the sheet had not finished showing. */
	func submittedSecret(
		_ field: SecretField,
		text: String,
		pending: PendingKeychainSecret
	) -> PendingKeychainSecret {
		editedSecretFields.contains(field) ? .edited(text.trimmed) : pending
	}
}
