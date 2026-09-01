/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

struct FileTransferApplicationScene: Scene {
	let center: FileTransferCenter

	var body: some Scene {
		Window(FileTransferStrings.fileTransfers, id: ApplicationSceneID.fileTransfers) {
			FileTransferCenterView(
				model: center.model,
				perform: center.perform,
				clearStopped: center.clearStoppedTransfers,
				close: {
					SharedApplication.sharedApplicationScenes().closeFileTransfers()
				},
				chooseDestination: center.completeDestinationSelection
			)
			.frame(
				minWidth: 620,
				idealWidth: 680,
				maxWidth: 1000,
				minHeight: 360,
				idealHeight: 440,
				maxHeight: 900
			)
		}
		.defaultSize(width: 680, height: 440)
		.windowResizability(.contentSize)
	}
}
