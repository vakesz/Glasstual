/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
	private func uniqueItem() -> KeychainItem {
		.serverPassword(UUID().uuidString)
	}

	@Test("A password written to the data-protection keychain reads back")
	func passwordRoundTrips() {
		let item = uniqueItem()
		defer { item.delete() }

		#expect(item.write("hunter2"))
		#expect(item.password == "hunter2")
	}

	/// The lookup used to fall through to the file keychain when the
	/// data-protection keychain reported errSecItemNotFound. It now reports
	/// that absence straight back to the caller, distinct from a refused read.
	@Test("A missing item reports that it is missing rather than searching elsewhere")
	func missingItemReportsNotFound() {
		let item = uniqueItem()

		#expect(item.readPassword() == .missing)
		#expect(item.password == nil)
	}

	/// deleteItem used to discard the result of a second, legacy delete; its
	/// return value now describes the one delete it performs.
	@Test("Deleting reports success once and failure afterwards")
	func deleteReportsTheDataProtectionResult() {
		let item = uniqueItem()

		#expect(item.write("hunter2"))
		#expect(item.delete())
		#expect(item.delete() == false)
	}
}
