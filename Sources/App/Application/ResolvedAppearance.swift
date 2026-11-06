// Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Combine
import Observation
import os

/// An immutable snapshot of the appearance the application is currently
/// drawing in. It is built once per appearance change and only ever read
/// afterwards, so it is a value.
struct ResolvedAppearance: Equatable, Sendable {
	var mode: AppearanceMode = .light
	/// Whether the appearance is the application's own choice rather than the
	/// system's. Only then does a window carry an `NSAppearance`.
	var overridesAppKitAppearance = false

	var isDarkAppearance: Bool {
		mode == .dark
	}

	var appKitAppearance: NSAppearance? {
		guard overridesAppKitAppearance else {
			return nil
		}

		return isDarkAppearance ? Self.appKitDarkAppearance() : Self.appKitLightAppearance()
	}

	@MainActor static func systemWideDarkModeEnabled() -> Bool {
		NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua]) != nil
	}

	static func appKitDarkAppearance() -> NSAppearance? {
		NSAppearance(named: .darkAqua)
	}

	static func appKitLightAppearance() -> NSAppearance? {
		NSAppearance(named: .aqua)
	}
}
