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
		XCTAssertEqual(
			PromptStrings.Plugin.loadApprovalBody(
				displayName: "Example",
				bundleIdentifier: "com.example.plugin",
				teamIdentifier: "TEAMID",
				location: "~/Library/Application Support/Glasstual/Plugins/Example.bundle"
			),
			"""
			The plugin “Example” has not been loaded before.

			Bundle identifier: com.example.plugin
			Team ID: TEAMID
			Location: ~/Library/Application Support/Glasstual/Plugins/Example.bundle

			\(pluginSecurityNotice)
			"""
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

	func testCatalogRetainsSchemaAndDocumentsConsolidatedAliases() throws {
		let catalog = try promptCatalog()
		XCTAssertEqual(catalog.sourceLanguage, "en")
		XCTAssertEqual(catalog.version, "1.0")
		XCTAssertEqual(catalog.strings.count, 97)

		let intentionalEmptyKeys: Set = ["6tj-yp", "f05-hu", "ztu-nv"]
		for (key, entry) in catalog.strings {
			XCTAssertTrue(entry.comment.hasPrefix("Migrated from legacy key \(key)."), key)
			XCTAssertEqual(entry.extractionState, "manual", key)
			let english = try XCTUnwrap(entry.localizations["en"], key)
			XCTAssertEqual(english.stringUnit.state, "translated", key)
			XCTAssertEqual(english.stringUnit.value.isEmpty, intentionalEmptyKeys.contains(key), key)
		}

		let aliases = [
			"0hh-sl": "sl5-rf",
			"c4z-2b": "2a3-5s",
			"dcc-c4": "qpv-go",
			"i8o-7z": "0kz-wd",
			"sv9-8s": "xca-5h",
			"u5k-9n": "c7s-dq",
		]
		for (alias, canonicalKey) in aliases {
			XCTAssertNil(catalog.strings[alias], alias)
			XCTAssertTrue(catalog.strings[canonicalKey]?.comment.contains(alias) == true, canonicalKey)
		}
	}

	func testCatalogRetainsEveryFormattedContract() throws {
		let formattedKeys: Set = [
			"0bj-ic", "2jq-t5", "2ul-cl", "3l6-3z", "3ze-xh", "45a-df", "4ua-v5", "5oq-vv",
			"85z-qw", "8ou-pu", "a9z-9f", "af6-45", "b4n-8z", "d22-76", "dcc-c2", "dcc-c3",
			"ezn-rm", "fjw-hj", "ihy-mz", "iun-45", "j6c-1v", "k3t-vq", "m8b-58", "mx1-qz",
			"nlz-um", "pnc-ew", "pq7-2k", "py0-cr", "sfx-xx", "xek-0t", "xfl-8e",
		]
		let catalog = try promptCatalog()
		let actualFormattedKeys = Set(catalog.strings.compactMap { key, entry in
			let value = entry.localizations["en"]?.stringUnit.value ?? ""
			return value.range(of: #"%(\d+\$)?@"#, options: .regularExpression) == nil ? nil : key
		})
		XCTAssertEqual(actualFormattedKeys, formattedKeys)
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
