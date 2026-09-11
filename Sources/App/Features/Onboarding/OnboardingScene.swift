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
			skipAction: {
				if session.skipRemainingSteps() {
					dismiss()
				}
			},
			cancelAction: {
				if session.cancel() {
					dismiss()
				}
			},
			setUpLaterAction: {
				if session.setUpLater() {
					dismiss()
				}
			}
		)
		/* The window keeps its close button even with the title bar hidden, and
		 closing it is the same decision as Cancel. A finished session ignores
		 this, so dismissing after Continue or Skip changes nothing. */
		.onDisappear(perform: session.windowDidClose)
	}

	private func dismiss() {
		dismissWindow(id: ApplicationSceneID.onboarding)
	}
}
