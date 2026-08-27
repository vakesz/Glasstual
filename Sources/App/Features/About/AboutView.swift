/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

@MainActor
struct AboutView: View {
	let content: AboutContent
	let applicationIcon: NSImage
	let openAcknowledgements: () -> Void
	let close: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			Image(nsImage: applicationIcon)
				.resizable()
				.scaledToFit()
				.frame(width: 98, height: 98)
				.accessibilityLabel(Text(verbatim: content.applicationIconAccessibilityLabel))
				.padding(.bottom, 14)

			Text(verbatim: content.applicationName)
				.font(.headline)
				.textSelection(.enabled)

			Text(verbatim: content.versionDescription)
				.font(.caption)
				.textSelection(.enabled)
				.padding(.top, 4)

			Text(verbatim: content.upstreamAttribution)
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.textSelection(.enabled)
				.padding(.top, 4)

			Spacer(minLength: 8)

			Button(action: openAcknowledgements) {
				Text(verbatim: content.acknowledgementsButtonTitle)
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 20)
		.padding(.bottom, 20)
		.frame(width: 218, height: 244)
		.onExitCommand(perform: close)
	}
}
