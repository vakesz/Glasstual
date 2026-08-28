/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import XCTest

final class PromptLocalizationMigrationTests: XCTestCase {
	func testApplicationActionsAndTypedPromptStateResolveLegacyValues() {
		XCTAssertEqual(PromptStrings.Action.accept, "Accept")
		XCTAssertEqual(PromptStrings.Action.cancel, "Cancel")
		XCTAssertEqual(PromptStrings.Action.confirmation, "OK")
		XCTAssertEqual(PromptStrings.Action.no, "No")
		XCTAssertEqual(PromptStrings.Action.yes, "Yes")
		XCTAssertEqual(PromptStrings.Deletion.confirmationTitle, "Do you want to delete the selection?")
		XCTAssertEqual(
			PromptStrings.Deletion.warning(for: .channel),
			"There is no undo and all data related to this channel, except for logs, will be erased."
		)
		XCTAssertEqual(
			PromptStrings.Deletion.warning(for: .query),
			"There is no undo and all data related to this query, except for logs, will be erased."
		)
		XCTAssertEqual(
			PromptStrings.Deletion.warning(for: .server),
			"There is no undo and all data related to this server, except for logs, will be erased."
		)
	}

	func testSemanticBoundariesPreservePositionalPlaceholderContracts() {
		XCTAssertEqual(
			PromptStrings.ConnectionLink.title(
				serverAddress: "irc.example.com",
				channelNames: "#swift",
				includesMultipleChannels: false
			),
			"You have clicked a link that will connect you to “irc.example.com“ and join the channel #swift"
		)
		XCTAssertEqual(
			PromptStrings.ConnectionLink.title(
				serverAddress: "irc.example.com",
				channelNames: "#swift, #macos",
				includesMultipleChannels: true
			),
			"You have clicked a link that will connect you to “irc.example.com“ and join the channels: #swift, #macos"
		)
	}

	func testTransportSecurityUsesTypedCipherStatus() {
		XCTAssertEqual(
			PromptStrings.TransportSecurity.cipherSummary(
				policyName: "TLS 1.3",
				cipherSuite: "TLS_AES_256_GCM_SHA384",
				status: .current
			),
			"TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384"
		)
		XCTAssertEqual(
			PromptStrings.TransportSecurity.cipherSummary(
				policyName: "TLS 1.2",
				cipherSuite: "TLS_RSA_WITH_AES_128_CBC_SHA",
				status: .deprecated
			),
			"TLS 1.2 with the cipher suite: TLS_RSA_WITH_AES_128_CBC_SHA (deprecated)"
		)
		XCTAssertEqual(
			PromptStrings.TransportSecurity.certificateSummary(
				policyName: "irc.example.com",
				cipherSummary: "TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384"
			),
			"""
			Encryption with a digital certificate keeps information private as it’s sent to or from the server “irc.example.com“

			Information encrypted using: TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384
			"""
		)
	}
}
