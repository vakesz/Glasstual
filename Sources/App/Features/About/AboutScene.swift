/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct AboutApplicationScene: Scene {
	var body: some Scene {
		/* An About box is a panel: it belongs above the windows it describes, it
		 is not something the Window menu lists or the system restores at the
		 next launch, and it holds nothing worth restoring. */
		UtilityWindow(AboutContent.current.applicationName, id: ApplicationSceneID.about) {
			AboutSceneRoot()
		}
		.windowResizability(.contentSize)
		.restorationBehavior(.disabled)
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
