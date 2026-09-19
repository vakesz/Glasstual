// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// Which web-search service the system is set to use, which is what the
/// transcript's Search command has to name. The menu is built with it and
/// validation refreshes it, so the item never says "Google" to someone whose
/// system is set to DuckDuckGo.
@MainActor
enum SystemWebSearch {
	private static let preferredWebServicesKey = "NSPreferredWebServices"
	private static let webSearchProviderKey = "NSWebServicesProviderWebSearch"
	private static let defaultDisplayNameKey = "NSDefaultDisplayName"
	private static let fallbackName = "Google"

	static var name: String {
		let services = UserDefaults.standard.dictionary(forKey: preferredWebServicesKey)
		let provider = services?[webSearchProviderKey]
			.flatMap(PropertyListValue.init(propertyList:))

		return provider?.dictionary?[defaultDisplayNameKey]?.string ?? fallbackName
	}

	static var menuTitle: String {
		ApplicationStrings.search(with: name)
	}
}
