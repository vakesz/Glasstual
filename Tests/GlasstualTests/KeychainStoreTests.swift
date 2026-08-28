/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Security
import Testing

@Suite("Keychain store", .serialized)
@MainActor
struct KeychainStoreTests {
	private static let kind = "application password"
	private static let service = "com.vakesz.glasstual.tests.keychain"

	private func uniqueName() -> String {
		"Glasstual test item \(UUID().uuidString)"
	}

	@Test("A password written to the data-protection keychain reads back")
	func passwordRoundTrips() {
		let name = uniqueName()
		defer { KeychainStore.deleteItem(name, kind: Self.kind, username: "user", service: Self.service) }

		#expect(
			KeychainStore.addItem(
				name,
				kind: Self.kind,
				username: "user",
				password: "hunter2",
				service: Self.service
			)
		)
		#expect(
			KeychainStore.password(
				forItem: name,
				kind: Self.kind,
				username: "user",
				service: Self.service
			) == "hunter2"
		)
	}

	/// The lookup used to fall through to the file keychain when the
	/// data-protection keychain reported errSecItemNotFound. It now reports
	/// that status straight back to the caller.
	@Test("A missing item reports errSecItemNotFound rather than searching elsewhere")
	func missingItemReportsNotFound() {
		var status = errSecSuccess
		let password = KeychainStore.password(
			forItem: uniqueName(),
			kind: Self.kind,
			username: "user",
			service: Self.service,
			status: &status
		)

		#expect(password == nil)
		#expect(status == errSecItemNotFound)
	}

	/// deleteItem used to discard the result of a second, legacy delete; its
	/// return value now describes the one delete it performs.
	@Test("Deleting reports success once and failure afterwards")
	func deleteReportsTheDataProtectionResult() {
		let name = uniqueName()
		#expect(
			KeychainStore.addItem(
				name,
				kind: Self.kind,
				username: "user",
				password: "hunter2",
				service: Self.service
			)
		)

		#expect(KeychainStore.deleteItem(name, kind: Self.kind, username: "user", service: Self.service))
		#expect(KeychainStore.deleteItem(name, kind: Self.kind, username: "user", service: Self.service) == false)
	}
}
