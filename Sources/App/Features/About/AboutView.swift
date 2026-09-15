/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

@MainActor
struct AboutView: View {
	let content: AboutContent
	let applicationIcon: Image
	let openAcknowledgements: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			applicationIcon
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

			if content.copyright.isEmpty == false {
				Text(verbatim: content.copyright)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.textSelection(.enabled)
					.padding(.top, 6)
			}

			Button(action: openAcknowledgements) {
				Text(verbatim: content.acknowledgementsButtonTitle)
			}
			.padding(.top, 18)
		}
		.padding(.horizontal, 24)
		.padding(.vertical, 24)
		/* Only the width is fixed: a panel sized to a number rather than to
		 its text left a band of empty space under the button, and grew one
		 when a longer translation wrapped. */
		.frame(width: 260)
	}
}
