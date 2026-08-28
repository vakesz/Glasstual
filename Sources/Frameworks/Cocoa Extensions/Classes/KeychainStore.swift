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

@objc(XRKeychain)
public final class KeychainStore: NSObject {
	@objc(deleteKeychainItem:withItemKind:forUsername:serviceName:)
	@discardableResult
	public static func deleteItem(_ name: String, kind: String, username: String?, service: String) -> Bool {
		let status = SecItemDelete(protectedQuery(
			name: name,
			kind: kind,
			username: username,
			service: service
		) as CFDictionary)
		return status == errSecSuccess
	}

	@objc(modifyOrAddKeychainItem:withItemKind:forUsername:withNewPassword:serviceName:)
	@discardableResult
	public static func modifyOrAddItem(
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
	@discardableResult
	public static func addItem(
		_ name: String,
		kind: String,
		username: String?,
		password: String,
		service: String
	) -> Bool {
		var query = protectedQuery(name: name, kind: kind, username: username, service: service)
		query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		query[kSecValueData] = Data(password.utf8)
		return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
	}

	@objc(getPasswordFromKeychainItem:withItemKind:forUsername:serviceName:)
	public static func password(forItem name: String, kind: String, username: String?, service: String) -> String? {
		password(forItem: name, kind: kind, username: username, service: service, status: nil)
	}

	@objc(getPasswordFromKeychainItem:withItemKind:forUsername:serviceName:returnedStatusCode:)
	public static func password(
		forItem name: String,
		kind: String,
		username: String?,
		service: String,
		status statusPointer: UnsafeMutablePointer<OSStatus>?
	) -> String? {
		var status = errSecSuccess
		var query = protectedQuery(name: name, kind: kind, username: username, service: service)
		let password = password(matching: &query, status: &status)
		statusPointer?.pointee = status
		return password
	}

	private static func protectedQuery(name: String, kind: String, username: String?,
	                                   service: String) -> [CFString: Any]
	{
		var query: [CFString: Any] = [
			kSecClass: kind == "internet password" ? kSecClassInternetPassword : kSecClassGenericPassword,
			kSecAttrLabel: name,
			kSecAttrDescription: kind,
			kSecAttrService: service,
			kSecUseDataProtectionKeychain: true,
		]
		if let username, username.isEmpty == false {
			query[kSecAttrAccount] = username
		}
		return query
	}

	private static func password(matching query: inout [CFString: Any], status: inout OSStatus) -> String? {
		query[kSecMatchLimit] = kSecMatchLimitOne
		query[kSecReturnData] = true
		var result: CFTypeRef?
		status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}
}
