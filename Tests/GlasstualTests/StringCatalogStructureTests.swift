/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Testing

/// Structural guarantees for every String Catalog in the repository.
///
/// These replace the entry counts and value digests the migration used to
/// pin: a count tells you a key was added or removed but not whether the
/// catalog is still usable, and it fails on every legitimate edit. What
/// actually has to hold is that Xcode can generate a distinct symbol for
/// every key, that no key is left looking dead, and that the placeholders
/// are internally consistent.
@Suite("String Catalog structure")
struct StringCatalogStructureTests {
	@Test("Every catalog declares English at version 1.0")
	func catalogsDeclareEnglishSchema() throws {
		for catalog in try StringCatalog.all() {
			#expect(catalog.sourceLanguage == "en", "\(catalog.name)")
			#expect(catalog.version == "1.0", "\(catalog.name)")
			#expect(catalog.strings.isEmpty == false, "\(catalog.name)")
		}
	}

	/// A key whose generated symbol collides with another key's is silently
	/// unreachable from Swift, so uniqueness is the property that matters
	/// rather than the spelling of any one key.
	@Test("Every key generates a distinct Swift symbol")
	func keysGenerateDistinctSymbols() throws {
		for catalog in try StringCatalog.all() {
			var symbols: [String: String] = [:]
			for key in catalog.strings.keys.sorted() {
				let symbol = StringCatalog.generatedSymbol(for: key)
				#expect(symbol.isEmpty == false, "\(catalog.name):\(key)")
				#expect(
					symbols[symbol] == nil,
					"\(catalog.name): “\(key)” and “\(symbols[symbol] ?? "")” both generate \(symbol)"
				)
				symbols[symbol] = key
			}
		}
	}

	/// Xcode offers to delete stale keys. Anything selected at runtime has to
	/// be marked "manual" instead, or a catalog clean-up silently removes it.
	@Test("No entry is left marked stale")
	func noEntryIsStale() throws {
		for catalog in try StringCatalog.all() {
			for (key, entry) in catalog.strings {
				#expect(entry.extractionState != "stale", "\(catalog.name):\(key)")
			}
		}
	}

	@Test("Every entry carries a translated English value")
	func everyEntryHasEnglish() throws {
		for catalog in try StringCatalog.all() {
			for (key, entry) in catalog.strings {
				let english = try #require(entry.localizations["en"], "\(catalog.name):\(key)")
				let units = english.stringUnits
				#expect(units.isEmpty == false, "\(catalog.name):\(key)")
				for unit in units {
					#expect(unit.state == "translated", "\(catalog.name):\(key)")
				}
			}
		}
	}

	/// A gap in the positional specifiers ("%1$@ %3$@") drops an argument at
	/// runtime, and a plural form that disagrees with its siblings changes
	/// the generated function's arity depending on the count.
	@Test("Placeholders are contiguous and agree across plural forms")
	func placeholdersAreConsistent() throws {
		for catalog in try StringCatalog.all() {
			for (key, entry) in catalog.strings {
				guard let english = entry.localizations["en"] else { continue }
				var shapes: Set<String> = []
				for unit in english.stringUnits {
					let indices = try StringCatalog.positionalIndices(in: unit.value)
					if let highest = indices.max() {
						#expect(
							indices == Set(1 ... highest),
							"\(catalog.name):\(key) skips a positional argument"
						)
					}
					try shapes.insert(StringCatalog.placeholderShape(of: unit.value))
				}
				#expect(shapes.count <= 1, "\(catalog.name):\(key) varies its placeholders by plural form")
			}
		}
	}

	/// The migration from the legacy `.strings` tables left keys named after
	/// Interface Builder object ids — `zjd-al`, `495-90` — which say nothing
	/// about what they hold. A readable key is one derived from its own text,
	/// so require every key to share a word with its value or its comment.
	@Test("Every key is derived from the text it names")
	func keysAreDerivedFromTheirText() throws {
		for catalog in try StringCatalog.all() {
			for (key, entry) in catalog.strings {
				// SecureTransport keys its entries by OSStatus.
				if Int(key) != nil {
					continue
				}
				var text: Set<String> = []
				for unit in entry.localizations["en"]?.stringUnits ?? [] {
					text.formUnion(StringCatalog.words(in: unit.value))
				}
				text.formUnion(StringCatalog.words(in: entry.comment ?? ""))
				#expect(
					StringCatalog.words(in: key).contains(where: { StringCatalog.matches($0, in: text) }),
					"\(catalog.name):\(key) shares no word with the string it names"
				)
			}
		}
	}
}

// MARK: - Catalog reading

private struct StringCatalog: Decodable {
	let sourceLanguage: String
	let strings: [String: Entry]
	let version: String
	var name = ""

	private enum CodingKeys: String, CodingKey {
		case sourceLanguage, strings, version
	}

	struct Entry: Decodable {
		var comment: String?
		var extractionState: String?
		var localizations: [String: Localization] = [:]
	}

	struct Localization: Decodable {
		var stringUnit: StringUnit?
		var variations: Variations?

		/// Every English spelling of the entry: one, or one per plural form.
		var stringUnits: [StringUnit] {
			if let stringUnit {
				return [stringUnit]
			}
			return (variations?.plural ?? [:]).keys.sorted().compactMap { variations?.plural?[$0]?.stringUnit }
		}
	}

	struct Variations: Decodable {
		var plural: [String: Localization]?
		var device: [String: Localization]?
	}

	struct StringUnit: Decodable {
		let state: String
		let value: String
	}

	static func all() throws -> [StringCatalog] {
		let sourcesURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources")
		guard let walker = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
			return []
		}

		var catalogs: [StringCatalog] = []
		for case let url as URL in walker where url.pathExtension == "xcstrings" {
			var catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
			catalog.name = url.deletingPathExtension().lastPathComponent
			catalogs.append(catalog)
		}
		return catalogs.sorted { $0.name < $1.name }
	}

	/// Xcode capitalises each `-` separated word, joins them, then lowercases
	/// the leading character when it is a letter.
	static func generatedSymbol(for key: String) -> String {
		let joined = key
			.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
			.map { $0.prefix(1).uppercased() + $0.dropFirst() }
			.joined()
		guard let first = joined.first else {
			return joined
		}
		return first.isLetter ? first.lowercased() + joined.dropFirst() : "_" + joined
	}

	/** Both helpers let a pattern that failed to compile throw. `try?` here made
	 a malformed pattern return an empty index set and an empty shape, which
	 reads exactly like a catalogue with nothing wrong in it, so the caller's
	 assertions would have checked nothing. */
	static func positionalIndices(in value: String) throws -> Set<Int> {
		var indices: Set<Int> = []
		let pattern = try NSRegularExpression(pattern: #"%(\d+)\$"#)
		let range = NSRange(value.startIndex ..< value.endIndex, in: value)
		pattern.enumerateMatches(in: value, range: range) { match, _, _ in
			guard let match, let digits = Range(match.range(at: 1), in: value) else { return }
			indices.insert(Int(value[digits]) ?? 0)
		}
		return indices
	}

	/// The specifiers a value uses, in order, ignoring the surrounding text.
	static func placeholderShape(of value: String) throws -> String {
		let pattern = try NSRegularExpression(
			pattern: #"%(\d+\$)?[-+ #0]*[\d.*]*(hh|h|ll|l|q|j|z|t|L)?[@diouxXeEfgGaAcsp]"#
		)
		let range = NSRange(value.startIndex ..< value.endIndex, in: value)
		var specifiers: [String] = []
		pattern.enumerateMatches(in: value, range: range) { match, _, _ in
			guard let match, let found = Range(match.range, in: value) else { return }
			specifiers.append(String(value[found]))
		}
		return specifiers.joined(separator: " ")
	}

	static func words(in text: String) -> Set<String> {
		Set(
			text.lowercased()
				.split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
				.map(String.init)
				.filter { $0.count >= 2 }
		)
	}

	/// Exact for short words, first-four-characters for longer ones so that
	/// "uptimes" still matches "uptime".
	static func matches(_ word: String, in text: Set<String>) -> Bool {
		if text.contains(word) {
			return true
		}
		guard word.count >= 4 else {
			return false
		}
		let stem = word.prefix(4)
		return text.contains { $0.count >= 4 && $0.hasPrefix(stem) }
	}
}
