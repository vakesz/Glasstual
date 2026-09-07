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

	@Test("Every entry opts into symbol generation or is manually extracted")
	func entriesAreEligibleForSymbolGeneration() throws {
		for catalog in try StringCatalog.all() {
			for (key, entry) in catalog.strings {
				#expect(entry.generatesSymbol ?? (entry.extractionState == "manual"), "\(catalog.name):\(key)")
			}
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

	@Test("Every supplied translation preserves argument positions and types")
	func placeholdersAreConsistent() throws {
		for catalog in try StringCatalog.all() {
			for (key, entry) in catalog.strings {
				let english = try #require(entry.localizations[catalog.sourceLanguage], "\(catalog.name):\(key)")
				let source = try #require(english.stringUnits.first, "\(catalog.name):\(key)")
				let shape = try StringCatalog.placeholderShape(of: source.value)
				for (language, localization) in entry.localizations {
					#expect(localization.stringUnits.isEmpty == false, "\(catalog.name):\(key):\(language)")
					for unit in localization.stringUnits {
						#expect(
							try StringCatalog.placeholderShape(of: unit.value) == shape,
							"\(catalog.name):\(key):\(language) changes the argument contract: \(unit.value)"
						)
					}
				}
			}
		}
	}

	@Test("Placeholder comparison permits reordering, repetition and formatting, not type changes")
	func placeholderFixtures() throws {
		#expect(try StringCatalog.placeholderShape(of: "%@ %lld") == StringCatalog
			.placeholderShape(of: "%2$lld %1$@ %1$@"))
		#expect(try StringCatalog.placeholderShape(of: "%d %%") == StringCatalog.placeholderShape(of: "%1$03i"))
		#expect(try StringCatalog.placeholderShape(of: "%@") != StringCatalog.placeholderShape(of: "%d"))
		#expect(throws: (any Error).self) { try StringCatalog.placeholderShape(of: "%1$@ %3$@") }
		#expect(throws: (any Error).self) { try StringCatalog.placeholderShape(of: "%1$@ %1$d") }
		#expect(throws: (any Error).self) { try StringCatalog.placeholderShape(of: "%1$@ %@") }
	}

	@Test("Device and plural variations are traversed recursively")
	func recursiveVariationFixture() throws {
		let data = Data("""
		{"variations":{"device":{"mac":{"variations":{"plural":{
		  "one":{"stringUnit":{"state":"translated","value":"%d item"}},
		  "other":{"stringUnit":{"state":"translated","value":"%d items"}}
		}}}}}}
		""".utf8)
		let localization = try JSONDecoder().decode(StringCatalog.Localization.self, from: data)
		#expect(localization.stringUnits.map(\.value).sorted() == ["%d item", "%d items"])
	}

	@Test("A missing or empty source inventory fails instead of passing vacuously")
	func missingInventoryFixture() throws {
		let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
		#expect(throws: (any Error).self) { try StringCatalog.all(in: directory) }
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(throws: (any Error).self) { try StringCatalog.all(in: directory) }
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
		var generatesSymbol: Bool?
		var localizations: [String: Localization] = [:]
	}

	struct Localization: Decodable {
		var stringUnit: StringUnit?
		var variations: [String: [String: Localization]]?

		var stringUnits: [StringUnit] {
			(stringUnit.map { [$0] } ?? []) + (variations ?? [:]).values.flatMap {
				$0.values.flatMap(\.stringUnits)
			}
		}
	}

	struct StringUnit: Decodable {
		let state: String
		let value: String
	}

	static func all(in directory: URL? = nil) throws -> [StringCatalog] {
		let sourcesURL = directory ?? URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources")
		guard let walker = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil) else {
			throw ContractError.missingCatalogs
		}

		var catalogs: [StringCatalog] = []
		for case let url as URL in walker where url.pathExtension == "xcstrings" {
			var catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
			catalog.name = url.deletingPathExtension().lastPathComponent
			catalogs.append(catalog)
		}
		guard catalogs.isEmpty == false else { throw ContractError.missingCatalogs }
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

	/// Compare argument slots, not textual order or presentation flags. A
	/// translation can repeat an argument but cannot change its ABI type.
	static func placeholderShape(of value: String) throws -> String {
		let pattern = try NSRegularExpression(
			pattern: #"%%|%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|h|ll|l|q|j|z|t|L)?([@diouxXeEfgGaAcsp])"#
		)
		let range = NSRange(value.startIndex ..< value.endIndex, in: value)
		var slots: [Int: String] = [:]
		var nextIndex = 1
		var positional: Bool?
		for match in pattern.matches(in: value, range: range) {
			let token = (value as NSString).substring(with: match.range)
			if token == "%%" {
				continue
			}
			let explicit = match.range(at: 1).location != NSNotFound
			guard positional == nil || positional == explicit else { throw ContractError.mixedPositions }
			positional = explicit
			let index = explicit ? Int((value as NSString).substring(with: match.range(at: 1))) ?? 0 : nextIndex
			nextIndex += 1
			let length = match.range(at: 2).location == NSNotFound ? "" : (value as NSString)
				.substring(with: match.range(at: 2))
			let conversion = (value as NSString).substring(with: match.range(at: 3))
			let kind = switch conversion {
			case "d", "i": "d"
			case "o", "u", "x", "X": "u"
			case "e", "E", "f", "g", "G", "a", "A": "f"
			default: conversion
			}
			let type = length + kind
			guard slots[index] == nil || slots[index] == type else { throw ContractError.conflictingTypes }
			slots[index] = type
		}
		if let highest = slots.keys.max() {
			guard highest > 0, Set(slots.keys) == Set(1 ... highest) else { throw ContractError.missingPosition }
		}
		return slots.keys.sorted().map { "\($0):\(slots[$0] ?? "")" }.joined(separator: " ")
	}

	private enum ContractError: Error {
		case mixedPositions, conflictingTypes, missingPosition, missingCatalogs
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
