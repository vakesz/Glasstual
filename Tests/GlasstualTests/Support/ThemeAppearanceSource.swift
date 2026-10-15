// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual

/// A stand-in for the application's appearance and contrast, so a test can
/// move them without touching the running application's settings.
@MainActor
final class ThemeAppearanceSource {
	var appearance = ThemeAppearance(isDark: false, increasesContrast: false)

	/// A store over `fixture`'s isolated defaults that resolves against this source.
	func makeStore(_ fixture: SettingsTransferFixture) -> ThemeStore {
		let store = ThemeStore(stores: fixture.stores) { self.appearance }
		store.reload()
		return store
	}
}
