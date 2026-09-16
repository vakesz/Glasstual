/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("App language selection")
struct AppLanguageTests {
	@Test("Missing app overrides follow the system, while explicit choices persist their language")
	func overrides() {
		#expect(AppLanguage(override: nil) == .system)
		#expect(AppLanguage(override: []) == .system)
		#expect(AppLanguage.system.override == nil)
		for language in AppLanguage.allCases where language != .system {
			#expect(AppLanguage(override: language.override) == language)
		}
	}

	@Test("Overrides from macOS language settings resolve regional variants and fallback order")
	func regionalOverrides() {
		#expect(AppLanguage(override: ["de-DE"]) == .german)
		#expect(AppLanguage(override: ["hu-HU"]) == .hungarian)
		#expect(AppLanguage(override: ["en-GB"]) == .english)
		#expect(AppLanguage(override: ["fr", "hu"]) == .hungarian)
	}

	@Test("Language overrides use the app domain without registering or exporting a default")
	func storagePolicy() {
		let key = Preferences.Internals.appLanguages
		#expect(key.storage == .standard)
		#expect(key.registeredDefault == nil)
		#expect(key.traits.contains(.excludedFromExport))
	}
}
