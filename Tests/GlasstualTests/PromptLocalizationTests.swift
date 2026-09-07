/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Prompt localization")
struct PromptLocalizationTests {
	@Test("Shared buttons and typed deletion prompts select the expected catalog entries")
	func applicationActionsAndTypedPromptStateResolveLegacyValues() throws {
		try expectLocalizedCopy(PromptStrings.Action.accept, .Prompts.actionTitleForAcceptingAccept, "Accept")
		try expectLocalizedCopy(PromptStrings.Action.cancel, .Prompts.cancel, "Cancel")
		try expectLocalizedCopy(PromptStrings.Action.confirmation, .Prompts.genericAcknowledgementButtonTitleOk, "OK")
		try expectLocalizedCopy(PromptStrings.Action.no, .Prompts.no, "No")
		try expectLocalizedCopy(PromptStrings.Action.yes, .Prompts.yes, "Yes")
		try expectLocalizedCopy(PromptStrings.Deletion.confirmationTitle, .Prompts.doYouWantToDelete,
		                        "Do you want to delete the selection?")
		let cases: [(PromptDeletionTarget, (LocalizedStringResource, String))] = [
			(.channel, (.Prompts.thereIsNoUndoAndAll, "channel")),
			(.query, (.Prompts.thereIsNoUndoAndAllDataRelated, "query")),
			(.server, (.Prompts.thereIsNoUndoAndAll2, "server")),
		]
		for (target, (resource, noun)) in cases {
			try expectLocalizedCopy(PromptStrings.Deletion.warning(for: target), resource,
			                        "There is no undo and all data related to this \(noun), except for logs, will be erased.")
		}
	}

	@Test("A connection link prompt names one channel or a list of them")
	func semanticBoundariesPreservePositionalPlaceholderContracts() throws {
		try expectLocalizedCopy(PromptStrings.ConnectionLink.title(
			serverAddress: "irc.example.com", channelNames: "#swift", includesMultipleChannels: false
		), .Prompts.youHaveClickedALink("irc.example.com", "#swift"),
		"You have clicked a link that will connect you to “irc.example.com“ and join the channel #swift")
		try expectLocalizedCopy(PromptStrings.ConnectionLink.title(
			serverAddress: "irc.example.com", channelNames: "#swift, #macos", includesMultipleChannels: true
		), .Prompts.youHaveClickedALinkThatWillConnect("irc.example.com", "#swift, #macos"),
		"You have clicked a link that will connect you to “irc.example.com“ and join the channels: #swift, #macos")
	}

	@Test("The transport security summary marks a deprecated cipher suite")
	func transportSecurityUsesTypedCipherStatus() throws {
		try expectLocalizedCopy(PromptStrings.TransportSecurity.cipherSummary(
			policyName: "TLS 1.3", cipherSuite: "TLS_AES_256_GCM_SHA384", status: .current
		), .Prompts.withTheCipherSuite("TLS 1.3", "TLS_AES_256_GCM_SHA384"),
		"TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384")
		try expectLocalizedCopy(PromptStrings.TransportSecurity.cipherSummary(
			policyName: "TLS 1.2", cipherSuite: "TLS_RSA_WITH_AES_128_CBC_SHA", status: .deprecated
		), .Prompts.withTheCipherSuiteDeprecated("TLS 1.2", "TLS_RSA_WITH_AES_128_CBC_SHA"),
		"TLS 1.2 with the cipher suite: TLS_RSA_WITH_AES_128_CBC_SHA (deprecated)")
		let cipher = "TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384"
		try expectLocalizedCopy(PromptStrings.TransportSecurity.certificateSummary(
			policyName: "irc.example.com", cipherSummary: cipher
		), .Prompts.encryptionWithADigitalCertificateKeepsInformation("irc.example.com", cipher), """
		Encryption with a digital certificate keeps information private as it’s sent to or from the server “irc.example.com“

		Information encrypted using: TLS 1.3 with the cipher suite: TLS_AES_256_GCM_SHA384
		""")
	}
}
