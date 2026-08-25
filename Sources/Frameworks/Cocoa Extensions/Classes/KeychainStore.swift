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

import Darwin
import Foundation
import Security

@objc(XRKeychain)
public final class KeychainStore: NSObject {
	@objc(deleteKeychainItem:withItemKind:forUsername:serviceName:)
	public class func deleteItem(_ name: String, kind: String, username: String?, service: String) -> Bool {
		let status = SecItemDelete(protectedQuery(
			name: name,
			kind: kind,
			username: username,
			service: service
		) as CFDictionary)
		_ = deleteLegacyItem(name: name, kind: kind, username: username, service: service)
		return status == errSecSuccess
	}

	@objc(modifyOrAddKeychainItem:withItemKind:forUsername:withNewPassword:serviceName:)
	public class func modifyOrAddItem(
		_ name: String,
		kind: String,
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

	@objc(addKeychainItem:withItemKind:forUsername:withPassword:serviceName:)
	public class func addItem(
		_ name: String,
		kind: String,
		username: String?,
		password: String,
		service: String
	) -> Bool {
		var query = protectedQuery(name: name, kind: kind, username: username, service: service)
		query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		query[kSecValueData] = Data(password.utf8)
		let status = SecItemAdd(query as CFDictionary, nil)
		if status == errSecSuccess {
			_ = deleteLegacyItem(name: name, kind: kind, username: username, service: service)
		}
		return status == errSecSuccess
	}

	@objc(getPasswordFromKeychainItem:withItemKind:forUsername:serviceName:)
	public class func password(forItem name: String, kind: String, username: String?, service: String) -> String? {
		password(forItem: name, kind: kind, username: username, service: service, status: nil)
	}

	@objc(getPasswordFromKeychainItem:withItemKind:forUsername:serviceName:returnedStatusCode:)
	public class func password(
		forItem name: String,
		kind: String,
		username: String?,
		service: String,
		status statusPointer: UnsafeMutablePointer<OSStatus>?
	) -> String? {
		var status = errSecSuccess
		var query = protectedQuery(name: name, kind: kind, username: username, service: service)
		var password = password(matching: &query, status: &status)
		if status == errSecItemNotFound {
			password = migrateLegacyItem(name: name, kind: kind, username: username, service: service, status: &status)
		}
		statusPointer?.pointee = status
		return password
	}

	private class func baseQuery(name: String, kind: String, username: String?, service: String) -> [CFString: Any] {
		var query: [CFString: Any] = [
			kSecClass: kind == "internet password" ? kSecClassInternetPassword : kSecClassGenericPassword,
			kSecAttrLabel: name,
			kSecAttrDescription: kind,
			kSecAttrService: service,
		]
		if let username, username.isEmpty == false {
			query[kSecAttrAccount] = username
		}
		return query
	}

	private class func protectedQuery(name: String, kind: String, username: String?,
	                                  service: String) -> [CFString: Any]
	{
		var query = baseQuery(name: name, kind: kind, username: username, service: service)
		query[kSecUseDataProtectionKeychain] = true
		return query
	}

	private class func legacyQuery(name: String, kind: String, username: String?, service: String) -> [CFString: Any]? {
		var keychain: SecKeychain?
		typealias CopyDefaultKeychain = @convention(c) (UnsafeMutablePointer<SecKeychain?>?) -> OSStatus
		guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecKeychainCopyDefault") else { return nil }
		let copyDefault = unsafeBitCast(symbol, to: CopyDefaultKeychain.self)
		guard copyDefault(&keychain) == errSecSuccess, let keychain else { return nil }
		var query = baseQuery(name: name, kind: kind, username: username, service: service)
		query[kSecMatchSearchList] = [keychain]
		return query
	}

	private class func deleteLegacyItem(name: String, kind: String, username: String?, service: String) -> Bool {
		guard let query = legacyQuery(name: name, kind: kind, username: username, service: service)
		else { return false }
		return SecItemDelete(query as CFDictionary) == errSecSuccess
	}

	private class func password(matching query: inout [CFString: Any], status: inout OSStatus) -> String? {
		query[kSecMatchLimit] = kSecMatchLimitOne
		query[kSecReturnData] = true
		var result: CFTypeRef?
		status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	private class func migrateLegacyItem(
		name: String,
		kind: String,
		username: String?,
		service: String,
		status: inout OSStatus
	) -> String? {
		guard var query = legacyQuery(name: name, kind: kind, username: username, service: service),
		      let password = password(matching: &query, status: &status)
		else { return nil }
		_ = addItem(name, kind: kind, username: username, password: password, service: service)
		return password
	}
}
