// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Observation

/** The window's toolbar and its sidebar footer.

 Two switches that sit in the window's frame rather than in either column, and
 neither of them is state this owns: one is a request the toolbar's search field
 answers, the other is a reading of the notification controller's mute switch.
 They are here so a change to either redraws the chrome and nothing else -- the
 columns and the sheet chain are on models of their own. */
@MainActor
@Observable
final class MainWindowChrome {
	/** Mirrors the toolbar search field's focus. The root view keeps it in step
	 with its `@FocusState` in both directions, so setting it is what moves the
	 keyboard into the field and clicking away is what clears it. */
	var isSearchFieldFocused = false
	/** Mirrors the notification controller's mute switch so the footer menu can
	 tick it. The controller is not observable and the switch is thrown from the
	 main menu as well, so the coordinator that owns the switch writes it here
	 whenever it changes. */
	var areNotificationsDisabled = false
	var connection: MainWindowConnectionPresentation?

	/// Puts the keyboard in the sidebar filter field, which now lives in the
	/// window toolbar. Channel Spotlight has a command of its own.
	func focusSearchField() {
		isSearchFieldFocused = true
	}
}
