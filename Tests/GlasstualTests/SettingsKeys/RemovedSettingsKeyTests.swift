// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/** The registration domain is built from the declarations, so a setting whose
 owner has been removed cannot linger in it.

 This used to be a hand-kept list of names that had been retired, which said
 nothing about the names that had not. The invariant is the stronger one: every
 name in the registration domain that is spelled the way this application
 spells one is a name the declarations still carry. AppKit, Foundation and the
 test runner register into the same domain, so the check is limited to names
 that use the `Group -> Name` scheme, which is what makes a name ours. */
@Suite("Removed settings keys")
@MainActor
struct RemovedSettingsKeyTests {
	@Test("Nothing of ours is registered that no declaration names")
	func registrationDomainCarriesOnlyDeclarations() {
		SettingsRegistration.registerDefaults()

		let declared = Set(SettingsKeys.allKeys.map(\.name))
		let registered = SettingsRegistration.registeredDefaults.keys.filter { $0.contains(" -> ") }

		#expect(registered.isEmpty == false, "the registration domain holds none of our declarations")

		for name in registered {
			#expect(declared.contains(name), "\(name) is registered but nothing declares it")
		}
	}

	/// The two keys 2.0.0 dropped outright: a dictionary-version counter nothing
	/// read, and a sheet setting no UI ever looked at.
	@Test(
		"A dropped setting is gone from the declarations",
		arguments: ["Dictionary Version", "Include Advanced Encodings"]
	)
	func droppedSettingsAreNotDeclared(name: String) {
		#expect(SettingsKeys.key(named: "Internals -> \(name)") == nil)
	}
}
