// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Observation
import Synchronization
import Testing

@MainActor
@Suite("Theme store")
struct ThemeStoreTests {
	/// Whether reading `read` registered a dependency that `change` invalidates.
	private func invalidates(_ read: () -> Void, when change: () -> Void) -> Bool {
		let fired = Mutex(false)
		withObservationTracking(read) {
			fired.withLock { $0 = true }
		}
		change()
		return fired.withLock { $0 }
	}

	/** The conversation background read the application's appearance, which
	 nothing observes, so the main window rebuilt the whole transcript to get
	 the background redrawn. */
	@Test("The background is observed through the appearance it resolves against")
	func backgroundFollowsAppearance() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let store = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}
		let light = store.backgroundColor

		let invalidated = invalidates {
			_ = store.backgroundColor
		} when: {
			source.appearance.isDark = true
			store.appearanceDidChange()
		}

		#expect(invalidated)
		#expect(store.backgroundColor == TranscriptTheme.lines.palette.background.resolved(
			isDark: true,
			increasesContrast: false
		))
		#expect(store.backgroundColor != light)
	}

	@Test("Increased contrast resolves the stronger colours")
	func contrastIsPartOfTheSnapshot() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let store = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}

		source.appearance.increasesContrast = true
		store.appearanceDidChange()

		let link = TranscriptTheme.lines.palette.link
		#expect(store.snapshot.increasesContrast)
		#expect(store.resolved(link) == link.resolved(isDark: false, increasesContrast: true))
	}

	/// The columns stand on the theme's chrome ground rather than on a
	/// material, so the store resolves it like any other role.
	@Test("The chrome ground resolves the palette's chrome role")
	func chromeFollowsTheme() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let store = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}

		#expect(store.chromeBackground == TranscriptTheme.lines.palette.chromeBackground.resolved(
			isDark: false,
			increasesContrast: false
		))
		source.appearance.isDark = true
		store.appearanceDidChange()
		#expect(store.chromeBackground == TranscriptTheme.lines.palette.chromeBackground.resolved(
			isDark: true,
			increasesContrast: false
		))
	}

	/// An announcement that is not news would rebuild every transcript.
	@Test("Only a moved appearance invalidates and announces")
	func unchangedAppearanceIsQuiet() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let store = source.makeStore(fixture)
		let announcements = Mutex(0)
		let token = NotificationCenter.default.addObserver(
			forName: .themeAppearanceChanged,
			object: store,
			queue: nil
		) { _ in
			announcements.withLock { $0 += 1 }
		}
		defer {
			NotificationCenter.default.removeObserver(token)
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}

		let invalidated = invalidates({ _ = store.backgroundColor }, when: store.appearanceDidChange)
		#expect(invalidated == false)
		#expect(announcements.withLock { $0 } == 0)

		source.appearance.isDark = true
		store.appearanceDidChange()
		#expect(announcements.withLock { $0 } == 1)
	}
}
