/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

import Foundation
import os
import Security

private let keychainLogger = Logger(
	subsystem: Logging.frameworkSubsystem,
	category: "Keychain"
)

/** An edit to a keychain-backed secret that has not been flushed yet.

 A model whose secret lives in the keychain cannot say "the user emptied the
 field" with `nil`: `nil` is also what a model nobody has edited carries, and
 flushing that one has to leave the stored secret alone. Telling the two apart
 is what this type is for, so an emptied field deletes the item instead of
 falling back to it forever. */
public enum PendingKeychainSecret: Sendable, Equatable, Hashable {
	/// Nothing is outstanding: the keychain item stands as it is.
	case unchanged
	/// A secret the user typed, waiting to be written.
	case set(String)
	/// The field was emptied: the keychain item goes when the edit is flushed.
	case cleared

	/// The edit a field that always knows its own contents makes, where an
	/// empty field means the secret is gone.
	public static func edited(_ text: String) -> Self {
		text.isEmpty ? .cleared : .set(text)
	}

	/// `nil` means the secret is gone, so it clears rather than doing nothing.
	/// So does an empty string: a field holding no characters is a field the
	/// user emptied, and writing `""` back would leave a keychain item behind
	/// that answers every later read with a password nobody typed.
	public init(_ value: String?) {
		self = value.map(Self.edited) ?? .cleared
	}

	/// The secret this edit resolves to, `stored` standing in when nothing is
	/// outstanding.
	public func value(orStored stored: @autoclosure () -> String?) -> String? {
		switch self {
		case .unchanged: stored()
		case let .set(value): value
		case .cleared: nil
		}
	}

	/// The same secret spelled out, so it survives a move to a keychain item
	/// under another identifier: an untouched secret becomes the stored one.
	public func detached(from stored: @autoclosure () -> String?) -> Self {
		guard case .unchanged = self else { return self }
		return stored().map(Self.set) ?? .unchanged
	}
}

/// One of the four secrets Glasstual keeps out of its property lists, named by
/// the model that owns it rather than by the label and service-name strings it
/// expands to. Every secret is scoped to the owning model's `uniqueIdentifier`,
/// which is what the associated value carries.
public enum KeychainItem: Sendable, Equatable, Hashable {
	case nicknamePassword(String)
	case proxyPassword(String)
	case serverPassword(String)
	case channelSecretKey(String)

	/// `kSecAttrLabel`. This is what Keychain Access shows the user.
	public var label: String {
		switch self {
		case .nicknamePassword: "Glasstual (NickServ)"
		case .proxyPassword: "Glasstual (Proxy Server Password)"
		case .serverPassword: "Glasstual (Server Password)"
		case .channelSecretKey: "Glasstual (Channel JOIN Key)"
		}
	}

	/// `kSecAttrService`. The prefix names the kind of secret; the suffix is the
	/// owning model's unique identifier.
	public var service: String {
		switch self {
		case let .nicknamePassword(identifier): "glasstual.nickserv.\(identifier)"
		case let .proxyPassword(identifier): "glasstual.proxy-server.\(identifier)"
		case let .serverPassword(identifier): "glasstual.server.\(identifier)"
		case let .channelSecretKey(identifier): "glasstual.channel-key.\(identifier)"
		}
	}

	/** The `kSecAttrService` actually stored: ``service``, except in a Debug
	 build running the unit tests or a UI review, where it is prefixed.

	 Those runs set `GLASSTUAL_UI_REVIEW_SUITE` or
	 `GLASSTUAL_UI_REVIEW_DIRECTORY` to keep off the user's real settings and
	 files, and the prefix does the same for secrets: the tests run inside the
	 application and share its access group, so without it a test item and a
	 real one with the same identifier would be one item. ``service`` is what a
	 shipping build writes, and what every other reader of these names asks for. */
	public var storedService: String {
		KeychainStore.isolatedServicePrefix + service
	}

	/// The stored secret, or `nil` when the item is absent or unreadable.
	public var password: String? {
		KeychainStore.readPassword(service: storedService)
	}

	/// Writes `password`, creating the item when it does not exist yet.
	@discardableResult
	public func write(_ password: String) -> Bool {
		KeychainStore.modifyOrAddItem(label, newPassword: password, service: storedService) == errSecSuccess
	}

	@discardableResult
	public func delete() -> Bool {
		KeychainStore.deleteItem(service: storedService) == errSecSuccess
	}

	/// Writes or deletes the item so it matches `secret`. `.unchanged` leaves
	/// whatever is stored alone.
	@discardableResult
	public func apply(_ secret: PendingKeychainSecret) -> KeychainWriteResult {
		let status: OSStatus
		switch secret {
		case .unchanged: return .saved
		case let .set(password):
			status = KeychainStore.modifyOrAddItem(label, newPassword: password, service: storedService)
		case .cleared:
			status = KeychainStore.deleteItem(service: storedService)
			if status == errSecItemNotFound {
				return .saved
			}
		}
		return status == errSecSuccess ? .saved : .failed(status)
	}
}

/// The result of a requested secret edit. Failure preserves the pending edit.
public enum KeychainWriteResult: Sendable, Equatable {
	case saved
	case failed(OSStatus)

	public func get() throws {
		if case let .failed(status) = self {
			throw KeychainWriteError(status: status)
		}
	}
}

public struct KeychainWriteError: Error, LocalizedError, Sendable {
	public let status: OSStatus

	public init(status: OSStatus) {
		self.status = status
	}

	public var errorDescription: String? {
		SecCopyErrorMessageString(status, nil) as String?
	}
}

/// Serializes each batch without suspension between its individual mutations.
public actor KeychainWriter {
	public static let shared = KeychainWriter()

	public func apply(_ edits: [KeychainItem: PendingKeychainSecret]) async throws {
		try Task.checkCancellation()
		for (item, edit) in edits {
			try item.apply(edit).get()
		}
	}
}

/// The `SecItem` calls behind ``KeychainItem``. The four cases of that enum are
/// the whole surface anything outside this framework needs.
///
/// Every item is written to, looked up in and deleted from one keychain access
/// group, ``accessGroup``. The application declares its own group, and the IRC
/// connection host — which holds only its own — cannot read any of them.
enum KeychainStore {
	/// Prepended to every stored service name in a Debug test or UI-review run;
	/// empty otherwise, and always empty in a Release build.
	static let isolatedServicePrefix: String = {
		#if DEBUG
			let environment = ProcessInfo.processInfo.environment
			let isIsolatedRun = ["GLASSTUAL_UI_REVIEW_SUITE", "GLASSTUAL_UI_REVIEW_DIRECTORY"].contains {
				environment[$0]?.isEmpty == false
			}
			return isIsolatedRun ? "glasstual.tests." : ""
		#else
			return ""
		#endif
	}()

	/** The one keychain access group these calls name, on every operation.

	 It is the first group of the running process's `keychain-access-groups`
	 entitlement, read from the process's own signature rather than spelled out
	 here: the string carries a team prefix the source does not know. That is
	 also the group an add without one lands in, so nothing about where a secret
	 is written changes. What changes is the lookup: it answers with an item in
	 this group and no other, so a secret an earlier build left in one of the
	 process's other groups can no longer shadow the one this build wrote, and
	 which of two items for one service wins is no longer unspecified.

	 `nil` in a process whose signature carries no such entitlement: there is no
	 group to name, and `SecItem` is left to its own default. */
	static let accessGroup: String? = {
		guard let task = SecTaskCreateFromSelf(nil) else {
			keychainLogger.error("Could not read this process's own signature to name a keychain access group")

			return nil
		}
		let entitlement = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
		guard let group = (entitlement as? [String])?.first else {
			keychainLogger.error("This process is entitled to no keychain access group")

			return nil
		}

		return group
	}()

	@discardableResult
	static func deleteItem(service: String) -> OSStatus {
		SecItemDelete(identityQuery(service: service) as CFDictionary)
	}

	@discardableResult
	static func modifyOrAddItem(
		_ name: String,
		newPassword: String?,
		service: String
	) -> OSStatus {
		var changes: [CFString: Any] = [
			kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
		]
		if let newPassword {
			changes[kSecValueData] = Data(newPassword.utf8)
		}
		let query = identityQuery(service: service)
		let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
		guard status == errSecItemNotFound else {
			return status
		}
		guard let newPassword, newPassword.isEmpty == false else {
			return errSecParam
		}

		/* An add can still collide: another process may have created the item
		 between the two calls, or one may exist with attributes this add does
		 not repeat. Updating the existing item is what the caller asked for,
		 so a duplicate is a second chance rather than a dropped password. */
		let addStatus = addItem(name, password: newPassword, service: service)
		return switch addStatus {
		case errSecDuplicateItem: SecItemUpdate(query as CFDictionary, changes as CFDictionary)
		default: addStatus
		}
	}

	/// Creates the item, reporting the `OSStatus` so a caller can tell a
	/// collision from a refusal.
	@discardableResult
	static func addItem(
		_ name: String,
		password: String,
		service: String
	) -> OSStatus {
		var query = identityQuery(service: service)
		/* Written once, at creation, and never looked up by: these are the two
		 attributes Keychain Access lets the user edit. */
		query[kSecAttrLabel] = name
		query[kSecAttrDescription] = "application password"
		query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		query[kSecValueData] = Data(password.utf8)
		return SecItemAdd(query as CFDictionary, nil)
	}

	/// The stored secret, or `nil` when the item is absent or the keychain
	/// refused the read.
	static func readPassword(service: String) -> String? {
		var query = identityQuery(service: service)
		query[kSecMatchLimit] = kSecMatchLimitOne
		query[kSecReturnData] = true

		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let data = result as? Data
		else {
			return nil
		}

		return String(data: data, encoding: .utf8)
	}

	/// The attributes that name one item and nothing else. Everything a user can
	/// rename in Keychain Access stays out of it, so renaming an item there does
	/// not hide it from the update that follows — which used to fail as
	/// `errSecItemNotFound`, then fail again as `errSecDuplicateItem` when the
	/// add ran, dropping the new password without saying so.
	///
	/// `kSecUseDataProtectionKeychain` is what makes ``accessGroup`` mean
	/// anything: without it macOS answers from the legacy file-based keychain,
	/// which has no access groups and ignores the attribute in silence.
	private static func identityQuery(service: String) -> [CFString: Any] {
		var query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: service,
			kSecUseDataProtectionKeychain: true,
		]
		if let accessGroup {
			query[kSecAttrAccessGroup] = accessGroup
		}

		return query
	}
}
