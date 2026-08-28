/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server properties sheet")
struct ServerPropertiesSheetMigrationTests {
	/// These sheets report value types, which cannot travel through
	/// `perform(_:with:with:)` or an `@objc` protocol, so their callbacks moved
	/// off the Objective-C selector surface and onto typed Swift protocols.
	@Test("The sheets that report values are reached through typed Swift delegates")
	func valueReportingSheetDelegatesAreTyped() {
		#expect((ServerPropertiesSheet.self as Any.Type) is (any ServerEndpointListSheetDelegate.Type))
		#expect((ServerPropertiesSheet.self as Any.Type) is (any HighlightEntrySheetDelegate.Type))
		#expect((ServerPropertiesSheet.self as Any.Type) is (any AddressBookSheetDelegate.Type))
		#expect((ServerPropertiesSheet.self as Any.Type) is (any ChannelPropertiesSheetDelegate.Type))
		#expect((TXMenuController.self as Any.Type) is (any ServerPropertiesSheetDelegate.Type))
	}

	/// The sheet's nib wires every one of these up by name, so a rename here is
	/// only found at runtime.
	@Test(
		"Every action the nib is wired to is still there",
		arguments: [
			"addAddressBookEntry:",
			"addChannel:",
			"addHighlight:",
			"autojoinWaitsForNickServChanged:",
			"cancel:",
			"deleteAddressBookEntry:",
			"deleteChannel:",
			"deleteHighlight:",
			"editAddressBookEntry:",
			"editChannel:",
			"editHighlight:",
			"editSeverEndpoints:",
			"ok:",
			"onClientCertificateChangeRequested:",
			"onClientCertificateFingerprintSHA1CopyRequested:",
			"onClientCertificateFingerprintSHA2CopyRequested:",
			"onClientCertificateFingerprintSHA512CopyRequested:",
			"onClientCertificateResetRequested:",
			"openProxySettingsInSystemPreferences:",
			"preferredCipherSuitesChanged:",
			"preferredCipherSuitesViewList:",
			"preferredInternetProtocolChanged:",
			"proxyTypeChanged:",
			"showAddAddressBookEntryMenu:",
			"toggleAdvancedEncodings:",
			"useSSLCheckChanged:",
		]
	)
	func nibActionSelectorsRemainAvailable(_ selector: String) {
		#expect(ServerPropertiesSheet.instancesRespond(to: NSSelectorFromString(selector)))
	}

	@Test("Identity fields accept what IRC accepts and nothing else")
	func identityValidationMatchesIRCRestrictions() {
		#expect(ServerPropertiesValidation.isNickname("valid_nick"))
		#expect(ServerPropertiesValidation.isNickname("invalid nickname") == false)
		#expect(ServerPropertiesValidation.isUsername("valid-user"))
		#expect(ServerPropertiesValidation.isUsername("invalid user") == false)
		#expect(ServerPropertiesValidation.areAlternateNicknamesValid("first second"))
		#expect(ServerPropertiesValidation.areAlternateNicknamesValid("first invalid!nick") == false)
	}

	@Test("An endpoint needs a host that resolves as a name or an address, and a port in range")
	func endpointValidationRejectsInvalidAddressesAndPorts() {
		#expect(ServerPropertiesValidation.isInternetAddress("irc.libera.chat"))
		#expect(ServerPropertiesValidation.isInternetAddress("2001:db8::1"))
		#expect(ServerPropertiesValidation.isInternetAddress("not a host") == false)
		#expect(ServerPropertiesValidation.isInternetPort("6697"))
		#expect(ServerPropertiesValidation.isInternetPort("0") == false)
		#expect(ServerPropertiesValidation.isInternetPort("70000") == false)
	}

	@Test("A disconnect message stays inside the protocol's length limit and on one line")
	func disconnectMessageValidationPreservesProtocolLimit() {
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 390)))
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 391)) == false)
		#expect(ServerPropertiesValidation.isLeavingComment("first\nsecond") == false)
	}
}
