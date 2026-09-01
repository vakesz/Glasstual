/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct OnboardingApplicationScene: Scene {
	var body: some Scene {
		Window(OnboardingStrings.Window.title, id: ApplicationSceneID.onboarding) {
			OnboardingSceneRoot()
		}
		.windowResizability(.contentSize)
		.windowStyle(.hiddenTitleBar)
	}
}

private struct OnboardingSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	@State private var session = OnboardingSession()

	var body: some View {
		OnboardingView(
			model: session.model,
			applicationIcon: Image(nsImage: NSApp.applicationIconImage),
			continueAction: {
				if session.continueFlow() {
					dismiss()
				}
			},
			backAction: session.moveBack,
			skipAction: dismiss
		)
		.onDisappear {
			session.markCompleted()
		}
	}

	private func dismiss() {
		session.markCompleted()
		dismissWindow(id: ApplicationSceneID.onboarding)
	}
}
