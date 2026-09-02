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
import Security

/// The keychain class an item lives in.
///
/// An item's identity is `kSecAttrService` together with `kSecAttrAccount`;
/// `descriptionAttribute` is written to `kSecAttrDescription`, which is not an
/// identity attribute. Every lookup query still filters on it, so the strings
/// below must keep matching what earlier releases wrote or the items those
/// releases created stop being found.
public enum KeychainItemClass: Sendable {
	case applicationPassword
	case internetPassword

	public var descriptionAttribute: String {
		switch self {
		case .applicationPassword: "application password"
		case .internetPassword: "internet password"
		}
	}

	var secClass: CFString {
		switch self {
		case .applicationPassword: kSecClassGenericPassword
		case .internetPassword: kSecClassInternetPassword
		}
	}
}

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
	public init(_ value: String?) {
		self = value.map(Self.set) ?? .cleared
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

	/// This edit when it carries one, and otherwise `fallback`'s.
	public func merged(over fallback: Self) -> Self {
		guard case .unchanged = self else { return self }
		return fallback
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
		case let .channelSecretKey(identifier): "glasstual.cjoinkey.\(identifier)"
		}
	}

	public var itemClass: KeychainItemClass {
		.applicationPassword
	}

	/// The stored secret, or `nil` when the item is absent or unreadable.
	public var password: String? {
		guard case let .found(password) = readPassword() else { return nil }

		return password
	}

	/// The stored secret, telling an absent item apart from a keychain that
	/// refused the read — which `password` cannot.
	public func readPassword() -> KeychainReadOutcome {
		KeychainStore.readPassword(label: label, kind: itemClass, username: nil, service: service)
	}

	/// Writes `password`, creating the item when it does not exist yet.
	@discardableResult
	public func write(_ password: String) -> Bool {
		KeychainStore.modifyOrAddItem(
			label,
			kind: itemClass,
			username: nil,
			newPassword: password,
			service: service
		)
	}

	@discardableResult
	public func delete() -> Bool {
		KeychainStore.deleteItem(label, kind: itemClass, username: nil, service: service)
	}

	/// Writes or deletes the item so it matches `secret`. `.unchanged` leaves
	/// whatever is stored alone.
	public func apply(_ secret: PendingKeychainSecret) {
		switch secret {
		case .unchanged: break
		case let .set(password): write(password)
		case .cleared: delete()
		}
	}
}

/// What reading one keychain item found.
public enum KeychainReadOutcome: Sendable, Equatable {
	case found(String)

	/// Nothing with this identity is in the keychain.
	case missing

	/// The keychain refused the read, reporting `status`.
	case failed(OSStatus)
}

/// The `SecItem` calls behind ``KeychainItem``. The four cases of that enum are
/// the whole surface anything outside this framework needs.
enum KeychainStore {
	@discardableResult
	static func deleteItem(
		_ name: String,
		kind: KeychainItemClass,
		username: String?,
		service: String
	) -> Bool {
		let status = SecItemDelete(protectedQuery(
			name: name,
			kind: kind,
			username: username,
			service: service
		) as CFDictionary)
		return status == errSecSuccess
	}

	@discardableResult
	static func modifyOrAddItem(
		_ name: String,
		kind: KeychainItemClass,
		username: String?,
		newPassword: String?,
		service: String
	) -> Bool {
		var changes: [CFString: Any] = [
			kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
		]
		if let newPassword {
			changes[kSecValueData] = Data(newPassword.utf8)
		}
		let status = SecItemUpdate(
			protectedQuery(name: name, kind: kind, username: username, service: service) as CFDictionary,
			changes as CFDictionary
		)
		if status == errSecItemNotFound, let newPassword, newPassword.isEmpty == false {
			return addItem(name, kind: kind, username: username, password: newPassword, service: service)
		}
		return status == errSecSuccess
	}

	@discardableResult
	static func addItem(
		_ name: String,
		kind: KeychainItemClass,
		username: String?,
		password: String,
		service: String
	) -> Bool {
		var query = protectedQuery(name: name, kind: kind, username: username, service: service)
		query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		query[kSecValueData] = Data(password.utf8)
		return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
	}

	static func readPassword(
		label: String,
		kind: KeychainItemClass,
		username: String?,
		service: String
	) -> KeychainReadOutcome {
		var query = protectedQuery(name: label, kind: kind, username: username, service: service)
		query[kSecMatchLimit] = kSecMatchLimitOne
		query[kSecReturnData] = true

		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)

		switch status {
		case errSecSuccess:
			guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
				return .failed(errSecDecode)
			}

			return .found(password)
		case errSecItemNotFound:
			return .missing
		default:
			return .failed(status)
		}
	}

	private static func protectedQuery(
		name: String,
		kind: KeychainItemClass,
		username: String?,
		service: String
	) -> [CFString: Any] {
		var query: [CFString: Any] = [
			kSecClass: kind.secClass,
			kSecAttrLabel: name,
			kSecAttrDescription: kind.descriptionAttribute,
			kSecAttrService: service,
			kSecUseDataProtectionKeychain: true,
		]
		if let username, username.isEmpty == false {
			query[kSecAttrAccount] = username
		}
		return query
	}
}
