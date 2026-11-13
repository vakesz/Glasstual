// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `ACCOUNTEXTBAN` names the extended ban that matches a services account. The
/// name is a word or a letter the network chooses, so the session reads it
/// instead of assuming `a`.
@MainActor
@Suite("ISUPPORT ACCOUNTEXTBAN")
struct ISupportAccountExtBanTests {
	@Test("The names the token lists are stored in order")
	func namesAreStored() {
		let support = ISupport()

		support.processConfigurationData("ACCOUNTEXTBAN=account,a")

		#expect(support.accountExtendedBanNames == ["account", "a"])
	}

	@Test("Empty entries are dropped")
	func emptyEntriesAreDropped() {
		#expect(ISupportTokenParser.accountExtendedBanNames(from: "account,,a,") == ["account", "a"])
		#expect(ISupportTokenParser.accountExtendedBanNames(from: "").isEmpty)
	}

	@Test("A negated token clears the names")
	func negationClearsTheNames() {
		let support = ISupport()

		support.processConfigurationData("ACCOUNTEXTBAN=account")
		support.processConfigurationData("-ACCOUNTEXTBAN")

		#expect(support.accountExtendedBanNames.isEmpty)
	}

	@Test("A reset forgets the names")
	func resetForgetsTheNames() {
		let support = ISupport()

		support.processConfigurationData("ACCOUNTEXTBAN=account")
		support.reset()

		#expect(support.accountExtendedBanNames.isEmpty)
	}

	@Test("The token is matched whatever its case")
	func tokenNameIsCaseInsensitive() {
		let support = ISupport()

		support.processConfigurationData("accountextban=account")

		#expect(support.accountExtendedBanNames == ["account"])
	}

	// MARK: - Building a mask

	@Test("The mask uses the prefix and the first name the server lists")
	func maskUsesTheFirstName() {
		let support = ISupport()

		support.processConfigurationData("EXTBAN=~,ac ACCOUNTEXTBAN=account,a")

		#expect(support.accountExtendedBanMask(for: "alice") == "~account:alice")
	}

	@Test("Without the token the mask falls back to the letter a")
	func maskFallsBackToTheLetter() {
		let support = ISupport()

		support.processConfigurationData("EXTBAN=~,ac")

		#expect(support.accountExtendedBanMask(for: "alice") == "~a:alice")
	}

	@Test("Without the token or the letter there is no mask")
	func noMaskWithoutAnAccountBan() {
		let support = ISupport()

		#expect(support.accountExtendedBanMask(for: "alice") == nil)

		support.processConfigurationData("EXTBAN=~,c")

		#expect(support.accountExtendedBanMask(for: "alice") == nil)
	}

	@Test("An account that cannot be written into a ban gives no mask", arguments: ["", "two words", "a,b"])
	func unusableAccountGivesNoMask(_ account: String) {
		let support = ISupport()

		support.processConfigurationData("EXTBAN=~,a ACCOUNTEXTBAN=account")

		#expect(support.accountExtendedBanMask(for: account) == nil)
	}

	// MARK: - Describing a mask

	@Test("A mask written with the account name is described as an account ban")
	func accountMaskIsDescribed() throws {
		let support = ISupport()

		support.processConfigurationData("EXTBAN=~,a ACCOUNTEXTBAN=account")

		let described = try #require(support.descriptionForExtendedBanMask("~account:foo"))
		let expected = ExtendedBanKind.describing(type: ExtendedBanKind.account.rawValue, argument: "foo")

		#expect(described == expected)
	}

	@Test("A negated account mask is described as an exception")
	func negatedAccountMaskIsDescribed() throws {
		let support = ISupport()

		/* With `~` as the prefix a second one is part of the body, so a
		 negation needs another prefix character to be told apart. */
		support.processConfigurationData("EXTBAN=$,a ACCOUNTEXTBAN=account")

		let described = try #require(support.descriptionForExtendedBanMask("$~account:foo"))
		let account = ExtendedBanKind.describing(type: ExtendedBanKind.account.rawValue, argument: "foo")

		#expect(described == String(localized: .IRC.everyoneExcept(account)))
	}

	@Test("The letter form is still described")
	func letterFormIsStillDescribed() {
		let support = ISupport()

		support.processConfigurationData("EXTBAN=~,a ACCOUNTEXTBAN=account")

		#expect(support.descriptionForExtendedBanMask("~a:foo") != nil)
	}

	@Test("An account name the server did not announce is not an account ban")
	func unannouncedNameIsNotDescribed() {
		let support = ISupport()

		support.processConfigurationData("EXTBAN=~,a ACCOUNTEXTBAN=account")

		#expect(support.descriptionForExtendedBanMask("~login:foo") == nil)
		#expect(support.descriptionForExtendedBanMask("~account:") == nil)
	}

	@Test("A server with no extended bans describes nothing")
	func noExtendedBansDescribesNothing() {
		let support = ISupport()

		support.processConfigurationData("ACCOUNTEXTBAN=account")

		#expect(support.descriptionForExtendedBanMask("~account:foo") == nil)
		#expect(support.accountExtendedBanMask(for: "foo") == nil)
	}
}
