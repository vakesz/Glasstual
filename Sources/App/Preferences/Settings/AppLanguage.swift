/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Which language the application runs in, as the General pane offers it.
nonisolated enum AppLanguage: String, CaseIterable, Sendable { // nonisolated: value
	case system
	case english = "en"
	case hungarian = "hu"
	case german = "de"

	/// The language codes the application ships, which is what a stored
	/// override is matched against. Adding a case is the whole change.
	private static let shipped = allCases.filter { $0 != .system }.map(\.rawValue)

	init(override: [String]?) {
		guard let override, override.isEmpty == false else {
			self = .system
			return
		}
		let match = Bundle.preferredLocalizations(from: Self.shipped, forPreferences: override).first
		self = match.flatMap(Self.init(rawValue:)) ?? .english
	}

	var override: [String]? {
		self == .system ? nil : [rawValue]
	}

	var title: LocalizedStringResource {
		switch self {
		case .system: .Settings.languageSystemDefault
		case .english: .Settings.languageEnglish
		case .hungarian: .Settings.languageHungarian
		case .german: .Settings.languageGerman
		}
	}
}
