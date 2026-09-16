/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Sendable { // nonisolated: value
	case system
	case english = "en"
	case hungarian = "hu"
	case german = "de"

	init(override: [String]?) {
		guard let override, override.isEmpty == false else {
			self = .system
			return
		}
		let match = Bundle.preferredLocalizations(from: ["en", "hu", "de"], forPreferences: override).first
		self = match.flatMap(Self.init(rawValue:)) ?? .english
	}

	var override: [String]? {
		self == .system ? nil : [rawValue]
	}
}

extension AppLanguage {
	var title: String {
		let resource: LocalizedStringResource = switch self {
		case .system: .Settings.languageSystemDefault
		case .english: .Settings.languageEnglish
		case .hungarian: .Settings.languageHungarian
		case .german: .Settings.languageGerman
		}
		return String(localized: resource)
	}
}
