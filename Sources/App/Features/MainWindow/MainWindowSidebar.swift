// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The sidebar column: the server list and nothing under it.

 Adding a server is in the toolbar and the File menu, and every other command
 is in the menu bar, so the sidebar keeps no footer of its own (the system's
 sidebars carry no Settings or overflow buttons). */
struct MainWindowSidebar: View {
	@Bindable var sidebar: Sidebar
	let redirectTyping: (String) -> Void

	private let settings = ObservableSettings.shared

	var body: some View {
		SidebarView(model: sidebar, redirectTyping: redirectTyping)
			/* The system's sidebar material by default. The theme's own chrome
			 ground, opaque, is drawn only when the reader asks the theme to
			 carry the window's chrome. */
			.background {
				if settings[SettingsKeys.Appearance.themesWindowChrome] {
					Rectangle()
						.fill(Color(nsColor: AppServices.theme.chromeBackground))
						.ignoresSafeArea(.container, edges: .top)
				}
			}
	}
}
