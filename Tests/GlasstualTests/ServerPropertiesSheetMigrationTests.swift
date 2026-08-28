/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class ServerPropertiesSheetMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNameRemainsStableForNibLoading() {
		XCTAssertEqual(NSStringFromClass(ServerPropertiesSheet.self), "TDCServerPropertiesSheet")
	}

	func testPublicAndDelegateSelectorsRemainAvailable() {
		let selectors = [
			"initWithClient:",
			"start",
			"startWithSelection:context:",
			"highlightEntrySheet:onOk:",
			"highlightEntrySheetWillClose:",
			"channelPropertiesSheet:onOk:",
			"channelPropertiesSheetWillClose:",
			"addressBookSheet:onOk:",
			"addressBookSheetWillClose:",
			"windowWillClose:",
		]

		for selector in selectors {
			XCTAssertTrue(ServerPropertiesSheet.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	/// The endpoint sheet reports a `[Server]` of value types, which cannot
	/// travel through `perform(_:with:with:)`, so those two callbacks moved off
	/// the Objective-C selector surface and onto a typed Swift protocol.
	func testServerEndpointListSheetDelegateIsTyped() {
		XCTAssertTrue((ServerPropertiesSheet.self as Any.Type) is (any ServerEndpointListSheetDelegate.Type))
	}

	func testNibActionSelectorsRemainAvailable() {
		let selectors = [
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

		for selector in selectors {
			XCTAssertTrue(ServerPropertiesSheet.instancesRespond(to: NSSelectorFromString(selector)), selector)
		}
	}

	func testIdentityValidationMatchesIRCRestrictions() {
		XCTAssertTrue(ServerPropertiesValidation.isNickname("valid_nick"))
		XCTAssertFalse(ServerPropertiesValidation.isNickname("invalid nickname"))
		XCTAssertTrue(ServerPropertiesValidation.isUsername("valid-user"))
		XCTAssertFalse(ServerPropertiesValidation.isUsername("invalid user"))
		XCTAssertTrue(ServerPropertiesValidation.areAlternateNicknamesValid("first second"))
		XCTAssertFalse(ServerPropertiesValidation.areAlternateNicknamesValid("first invalid!nick"))
	}

	func testEndpointValidationRejectsInvalidAddressesAndPorts() {
		XCTAssertTrue(ServerPropertiesValidation.isInternetAddress("irc.libera.chat"))
		XCTAssertTrue(ServerPropertiesValidation.isInternetAddress("2001:db8::1"))
		XCTAssertFalse(ServerPropertiesValidation.isInternetAddress("not a host"))
		XCTAssertTrue(ServerPropertiesValidation.isInternetPort("6697"))
		XCTAssertFalse(ServerPropertiesValidation.isInternetPort("0"))
		XCTAssertFalse(ServerPropertiesValidation.isInternetPort("70000"))
	}

	func testDisconnectMessageValidationPreservesProtocolLimit() {
		XCTAssertTrue(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 390)))
		XCTAssertFalse(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 391)))
		XCTAssertFalse(ServerPropertiesValidation.isLeavingComment("first\nsecond"))
	}
}
