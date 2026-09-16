/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct FileTransferScene: Scene {
	let center: FileTransferCenter

	var body: some Scene {
		Window(FileTransferStrings.fileTransfers, id: ApplicationSceneID.fileTransfers) {
			FileTransferCenterView(center: center)
				.frame(
					minWidth: 620,
					idealWidth: 680,
					minHeight: 360,
					idealHeight: 440
				)
		}
		.defaultSize(width: 680, height: 440)
		/* `contentSize` pins the window to its ideal size every time it opens,
		 which threw away whatever size the user had left it at. */
		.windowResizability(.contentMinSize)
	}
}
