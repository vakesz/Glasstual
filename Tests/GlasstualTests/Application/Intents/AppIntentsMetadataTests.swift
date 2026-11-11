// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/// Shortcuts, Siri and Spotlight learn the application's intents from the
/// metadata the build extracts into the bundle, not from the running code.
@Suite("App Intents metadata")
struct AppIntentsMetadataTests {
	private func metadata() throws -> [String: Any] {
		let directory = try #require(Bundle.main.url(forResource: "Metadata", withExtension: "appintents"))
		let data = try Data(contentsOf: directory.appending(path: "extract.actionsdata"))
		return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
	}

	@Test("The bundle declares every intent and the Focus filter")
	func declaresActions() throws {
		let actions = try #require(try metadata()["actions"] as? [String: Any])
		for name in [
			"SendMessageIntent",
			"JoinChannelIntent",
			"ConnectServerIntent",
			"DisconnectServerIntent",
			"OpenConversationIntent",
			"GlasstualFocusFilter",
		] {
			#expect(actions[name] != nil, "\(name)")
		}
	}

	@Test("The bundle names the App Shortcuts provider and its shortcuts")
	func declaresShortcutsProvider() throws {
		let metadata = try metadata()
		let provider = try #require(metadata["autoShortcutProviderMangledName"] as? String)
		#expect(provider.isEmpty == false)
		let shortcuts = try #require(metadata["autoShortcuts"] as? [[String: Any]])
		#expect(shortcuts.count == 5)
	}

	/// The extracted strings carry a key and a table, so a misspelt key only
	/// shows up when Shortcuts displays it.
	@Test("Every localized string in the metadata resolves in its table")
	func stringsResolve() throws {
		var references: [(key: String, table: String)] = []
		try collectReferences(in: metadata(), into: &references)
		#expect(references.isEmpty == false)
		let missing = "\u{0}missing"
		for reference in references {
			let value = Bundle.main.localizedString(forKey: reference.key, value: missing, table: reference.table)
			#expect(value != missing, "\(reference.table):\(reference.key)")
		}
	}

	private func collectReferences(in value: Any, into references: inout [(key: String, table: String)]) {
		if let dictionary = value as? [String: Any] {
			if let key = dictionary["key"] as? String, let table = dictionary["table"] as? String {
				references.append((key, table))
			}
			for child in dictionary.values {
				collectReferences(in: child, into: &references)
			}
		} else if let array = value as? [Any] {
			for child in array {
				collectReferences(in: child, into: &references)
			}
		}
	}
}
