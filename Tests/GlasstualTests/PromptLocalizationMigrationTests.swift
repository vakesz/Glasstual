/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import XCTest

@MainActor
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
		let pluginSecurityNotice = "Plugins run with the same access as Glasstual itself. "
			+ "Only load plugins from developers you trust. This choice is remembered until the plugin is signed "
			+ "by a different Team ID or the approvals are reset in Settings > Addons."
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

	/// Six legacy keys were duplicates of another entry's text. The survivors
	/// name the keys they absorbed so the consolidation stays traceable.
	func testConsolidatedAliasesAreDocumented() throws {
		let catalog = try promptCatalog()
		let aliases = ["0hh-sl", "c4z-2b", "dcc-c4", "i8o-7z", "sv9-8s", "u5k-9n"]

		for alias in aliases {
			XCTAssertNil(catalog.strings[alias], alias)
			XCTAssertTrue(
				catalog.strings.values.contains { $0.comment.contains(alias) },
				alias
			)
		}
	}

	func testLegacyPromptsTableIsRetired() {
		let legacyURL = languageFilesURL
			.appending(path: "en.lproj")
			.appending(path: "Prompts.strings")
		XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
	}

	private func promptCatalog() throws -> PromptCatalog {
		try JSONDecoder().decode(
			PromptCatalog.self,
			from: Data(contentsOf: languageFilesURL.appending(path: "Prompts.xcstrings"))
		)
	}

	private var languageFilesURL: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App/Resources/Language Files")
	}
}

private struct PromptCatalog: Decodable {
	let sourceLanguage: String
	let strings: [String: PromptCatalogEntry]
	let version: String
}

private struct PromptCatalogEntry: Decodable {
	let comment: String
	let extractionState: String
	let localizations: [String: PromptCatalogLocalization]
}

private struct PromptCatalogLocalization: Decodable {
	let stringUnit: PromptCatalogStringUnit
}

private struct PromptCatalogStringUnit: Decodable {
	let state: String
	let value: String
}
