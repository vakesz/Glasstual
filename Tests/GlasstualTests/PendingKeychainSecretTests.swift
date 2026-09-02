/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Testing

/// The secrets Glasstual keeps in the keychain used to carry their pending edit
/// as `String?`, where `nil` meant both "nobody touched this" and "the user
/// emptied the field". Flushing did nothing for `nil`, so an emptied field left
/// the old secret in the keychain and the getter fell straight back to it. The
/// three cases are what keep those apart.
@Suite("Pending keychain secret")
struct PendingKeychainSecretTests {
	@Test("An emptied field clears, a filled one sets")
	func editedTextDistinguishesClearingFromSetting() {
		#expect(PendingKeychainSecret.edited("") == .cleared)
		#expect(PendingKeychainSecret.edited("hunter2") == .set("hunter2"))
	}

	@Test("A nil assignment clears rather than leaving the stored secret behind")
	func nilClears() {
		#expect(PendingKeychainSecret(nil) == .cleared)
		#expect(PendingKeychainSecret("hunter2") == .set("hunter2"))
	}

	@Test("Only an untouched secret reads back what the keychain holds")
	func resolutionPrefersTheEdit() {
		#expect(PendingKeychainSecret.unchanged.value(orStored: "stored") == "stored")
		#expect(PendingKeychainSecret.set("typed").value(orStored: "stored") == "typed")
		#expect(PendingKeychainSecret.cleared.value(orStored: "stored") == nil)
	}

	/// A duplicate is keyed on a fresh identifier, so an untouched secret has to
	/// be spelled out before the copy can rewrite it under its own item.
	@Test("Detaching spells out an untouched secret and leaves an edit alone")
	func detachingCarriesTheStoredSecret() {
		#expect(PendingKeychainSecret.unchanged.detached(from: "stored") == .set("stored"))
		#expect(PendingKeychainSecret.unchanged.detached(from: nil) == .unchanged)
		#expect(PendingKeychainSecret.set("typed").detached(from: "stored") == .set("typed"))
		#expect(PendingKeychainSecret.cleared.detached(from: "stored") == .cleared)
	}

	@Test("Merging keeps the newer edit, including a clear")
	func mergingKeepsTheNewerEdit() {
		#expect(PendingKeychainSecret.unchanged.merged(over: .set("older")) == .set("older"))
		#expect(PendingKeychainSecret.set("newer").merged(over: .set("older")) == .set("newer"))
		#expect(PendingKeychainSecret.cleared.merged(over: .set("older")) == .cleared)
	}
}
