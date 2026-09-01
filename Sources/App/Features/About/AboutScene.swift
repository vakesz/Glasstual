/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct AboutApplicationScene: Scene {
	var body: some Scene {
		Window(AboutContent.current.applicationName, id: ApplicationSceneID.about) {
			AboutSceneRoot()
		}
		.windowResizability(.contentSize)
	}
}

private struct AboutSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow

	var body: some View {
		AboutView(
			content: .current,
			applicationIcon: Image(nsImage: NSApp.applicationIconImage),
			openAcknowledgements: {
				AppController.shared.menuController?.openAcknowledgements(nil)
			},
			close: {
				dismissWindow(id: ApplicationSceneID.about)
			}
		)
	}
}
