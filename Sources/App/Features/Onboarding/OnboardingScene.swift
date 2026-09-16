/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct OnboardingScene: Scene {
	var body: some Scene {
		Window(OnboardingStrings.Window.title, id: ApplicationSceneID.onboarding) {
			OnboardingSceneRoot()
		}
		.windowResizability(.contentMinSize)
		.windowStyle(.hiddenTitleBar)
	}
}

private struct OnboardingSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	@State private var session = OnboardingSession()

	var body: some View {
		OnboardingView(
			session: session,
			applicationIcon: Image(nsImage: NSApp.applicationIconImage),
			dismiss: { dismissWindow(id: ApplicationSceneID.onboarding) }
		)
		/* The window keeps its close button even with the title bar hidden.
		 Closing it applies nothing, but it still records that onboarding was
		 answered — leaving it unmarked is what made the window come back at
		 every launch. A finished session ignores this. */
		.onDisappear(perform: session.setUpLater)
	}
}
