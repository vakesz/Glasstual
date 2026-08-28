/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Prompt localization")
struct PromptLocalizationMigrationTests {
	@Test("The shared button titles and deletion copy keep their legacy wording")
	func applicationActionsAndTypedPromptStateResolveLegacyValues() {
		#expect(PromptStrings.Action.accept == "Accept")
		#expect(PromptStrings.Action.cancel == "Cancel")
		#expect(PromptStrings.Action.confirmation == "OK")
		#expect(PromptStrings.Action.no == "No")
		#expect(PromptStrings.Action.yes == "Yes")
		#expect(PromptStrings.Deletion.confirmationTitle == "Do you want to delete the selection?")
		#expect(
			PromptStrings.Deletion.warning(for: .channel)
				== "There is no undo and all data related to this channel, except for logs, will be erased."
		)
		#expect(
			PromptStrings.Deletion.warning(for: .query)
				== "There is no undo and all data related to this query, except for logs, will be erased."
		)
		#expect(
			PromptStrings.Deletion.warning(for: .server)
				== "There is no undo and all data related to this server, except for logs, will be erased."
		)
	}

	@Test("A connection link prompt names one channel or a list of them")
	func semanticBoundariesPreservePositionalPlaceholderContracts() {
		#expect(
			PromptStrings.ConnectionLink.title(
				serverAddress: "irc.example.com",
				channelNames: "#swift",
				includesMultipleChannels: false
			) == "You have clicked a link that will connect you to “irc.example.com“ and join the channel #swift"
		)
		#expect(
			PromptStrings.ConnectionLink.title(
				serverAddress: "irc.example.com",
				channelNames: "#swift, #macos",
				includesMultipleChannels: true
			) == """
			You have clicked a link that will connect you to “irc.example.com“ and join the channels: #swift, #macos
			"""
		)
	}

	@Test("The transport security summary marks a deprecated cipher suite")
	func transportSecurityUsesTypedCipherStatus() {
		#expect(
			PromptStrings.TransportSecurity.cipherSummary(
				policyName: "TLS 1.3",
				cipherSuite: "TLS_AES_256_GCM_SHA384",
				status: .current
			) == "TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384"
		)
		#expect(
			PromptStrings.TransportSecurity.cipherSummary(
				policyName: "TLS 1.2",
				cipherSuite: "TLS_RSA_WITH_AES_128_CBC_SHA",
				status: .deprecated
			) == "TLS 1.2 with the cipher suite: TLS_RSA_WITH_AES_128_CBC_SHA (deprecated)"
		)
		#expect(
			PromptStrings.TransportSecurity.certificateSummary(
				policyName: "irc.example.com",
				cipherSummary: "TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384"
			) == """
			Encryption with a digital certificate keeps information private as it’s sent to or from the server “irc.example.com“

			Information encrypted using: TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384
			"""
		)
	}
}
