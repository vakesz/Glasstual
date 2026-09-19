// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct HungarianGermanLocalizationTests {
	@Test("Hungarian and German cover every catalog variant and preserve format arguments")
	func catalogsAreComplete() throws {
		let sources = RepositoryPaths.sources
		let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
		let format =
			try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:[-+ #0]*\d*(?:\.\d+)?(?:ll|l|z|t|j|h|hh)?[@diuoxXfFeEgGaAcCsSp]|#@\w+@|arg)"#)
		var count = 0
		for case let url as URL in walker where url.pathExtension == "xcstrings" {
			let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
			let strings = try #require(catalog["strings"] as? [String: [String: Any]])
			for (key, entry) in strings {
				let locales = try #require(entry["localizations"] as? [String: [String: Any]])
				let english = try #require(locales["en"])
				let originals = units(in: english)
				for language in ["hu", "de"] {
					let translation = try #require(locales[language], "\(url.lastPathComponent): \(key), \(language)")
					let translated = units(in: translation)
					#expect(Set(originals.keys) == Set(translated.keys), "Missing variant: \(key), \(language)")
					for (path, source) in originals {
						let target = try #require(translated[path])
						#expect(source.isEmpty || target.isEmpty == false, "Empty translation: \(key), \(language)")
						#expect(
							tokens(in: source, using: format) == tokens(in: target, using: format),
							"Changed arguments: \(key), \(language)"
						)
						#expect(controls(in: source) == controls(in: target), "Changed IRC formatting: \(key), \(language)")
					}
				}
				count += 1
			}
		}
		#expect(count > 1700)
	}

	@Test("Compiled resources resolve each new language without changing the process language")
	func compiledResources() {
		for (language, expected) in [("hu", "Ajánlott csatornák"), ("de", "Empfohlene Kanäle")] {
			var resource = LocalizedStringResource.Onboarding.suggestedChannels
			resource.locale = Locale(identifier: language)
			#expect(String(localized: resource) == expected)
		}
	}

	private func units(in object: [String: Any], path: String = "") -> [String: String] {
		var result: [String: String] = [:]
		if let unit = object["stringUnit"] as? [String: String] {
			#expect(unit["state"] == "translated")
			result[path] = unit["value"]
		}
		for (key, value) in object where key != "stringUnit" {
			if let child = value as? [String: Any] {
				result.merge(units(in: child, path: path + "/" + key)) { first, _ in first }
			}
		}
		return result
	}

	private func tokens(in text: String, using regex: NSRegularExpression) -> [String] {
		regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
			(text as NSString).substring(with: $0.range)
		}.sorted()
	}

	private func controls(in text: String) -> [UInt32] {
		text.unicodeScalars.filter { $0.value < 32 && ![9, 10, 13].contains($0.value) }.map(\.value).sorted()
	}
}
