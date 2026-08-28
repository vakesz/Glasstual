/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CryptoKit
import Foundation
@testable import Glasstual
import XCTest

@MainActor
final class IRCStringCatalogMigrationTests: XCTestCase {
	func testCatalogRetainsAllLegacyKeysAndExactValueDigest() throws {
		let catalog = try loadCatalog()
		XCTAssertEqual(catalog.sourceLanguage, "en")
		XCTAssertEqual(catalog.version, "1.0")

		// Keys added after the migration are allowed; the guarantee is that every
		// key carried over from the legacy tables is still here, unchanged.
		let legacyKeys = catalog.strings.filter { key, entry in
			entry.comment.contains("Migrated from legacy key \(key)")
		}.keys.sorted()
		XCTAssertEqual(legacyKeys.count, 220)

		for (key, entry) in catalog.strings {
			XCTAssertEqual(entry.localizations["en"]?.stringUnit.state, "translated", key)
		}

		let canonicalValues = legacyKeys.map { key in
			let entry = catalog.strings[key]!

			return key + "\u{1F}" + (entry.localizations["en"]?.stringUnit.value ?? "")
		}.joined(separator: "\u{1E}")
		let digest = SHA256.hash(data: Data(canonicalValues.utf8))
		XCTAssertEqual(
			digest.map { String(format: "%02x", $0) }.joined(),
			"8c1298260a2cc6eb83172cbcbe2d2ba9409746d077d37fbfb28a54d13c6c43a5"
		)
	}

	func testGeneratedAndLegacyFormatterBoundariesPreservePlaceholders() {
		XCTAssertEqual(
			IRCCommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 390),
			"You have exceeded the maximum topic length for Libera.Chat which is 390 characters. "
				+ "The end of your topic may have been cut off."
		)
		XCTAssertEqual(
			IRCConnectionStrings.connecting(host: "irc.example", port: 6697),
			"Connecting to [irc.example] on port 6697"
		)
		XCTAssertEqual(
			IRCFileTransferStrings.request(nickname: "Alice", filename: "archive.zip", byteCount: 1024),
			"Received file transfer request from Alice, archive.zip (1024 bytes)"
		)
	}

	func testTypedDynamicSelectionsPreserveBehavior() {
		XCTAssertEqual(IRCTimerStrings.status(active: true), "Active")
		XCTAssertTrue(IRCTimerStrings.help(topic: .restart).contains("/timer restart <identifier>"))
		XCTAssertEqual(IRCCTCPStrings.lagRating(.excellent), "Yeah, okay…")
		XCTAssertEqual(IRCCTCPStrings.lagRating(.verySlow), "Very slow")
		XCTAssertEqual(
			IRCISupportStrings.extendedBanDescription(type: "a", argument: "staff"),
			"Users logged in to account “staff”"
		)
		XCTAssertEqual(
			IRCISupportStrings.extendedBanDescription(type: "?", argument: "mask"),
			"Extended ban of type “?”: mask"
		)
		XCTAssertEqual(
			IRCChannelAccessListStrings.entry(
				kind: .ban,
				channelName: "#swift",
				mask: "*!*@example",
				setBy: "Alice",
				date: "26 Aug 2026"
			),
			"Ban in #swift: *!*@example set by Alice on 26 Aug 2026"
		)
	}

	func testSetNameUsesRetainedCatalogEntry() {
		XCTAssertEqual(
			IRCCommandStrings.setNameUnsupported,
			"This server does not support changing the real name (setname)"
		)
	}

	private func loadCatalog() throws -> Catalog {
		let repositoryURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let catalogURL = repositoryURL
			.appending(path: "Sources/App/Resources/Language Files/IRC.xcstrings")

		return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
	}
}

private struct Catalog: Decodable {
	let sourceLanguage: String
	let strings: [String: CatalogEntry]
	let version: String
}

private struct CatalogEntry: Decodable {
	let comment: String
	let localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Decodable {
	let stringUnit: CatalogStringUnit
}

private struct CatalogStringUnit: Decodable {
	let state: String
	let value: String
}
