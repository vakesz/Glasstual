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

import AppKit
import SwiftUI

struct AboutScene: Scene {
	var body: some Scene {
		/* An About box is a panel: it belongs above the windows it describes, it
		 is not something the Window menu lists or the system restores at the
		 next launch, and it holds nothing worth restoring. */
		UtilityWindow(ApplicationInfo.applicationName(), id: ApplicationSceneID.about) {
			AboutView(
				applicationIcon: Image(nsImage: NSApp.applicationIconImage),
				openAcknowledgements: {
					AppServices.delegate.menuController?.openAcknowledgements(nil)
				}
			)
		}
		.windowResizability(.contentSize)
		.restorationBehavior(.disabled)
	}
}

@MainActor
struct AboutView: View {
	let applicationIcon: Image
	let openAcknowledgements: () -> Void

	/// `NSHumanReadableCopyright`, the same line the standard About panel
	/// shows. It already says this is a fork of Textual, so the panel says it
	/// once rather than twice.
	private var copyright: String {
		ApplicationInfo.applicationCopyright()
	}

	var body: some View {
		VStack(spacing: 0) {
			applicationIcon
				.resizable()
				.scaledToFit()
				.frame(width: 98, height: 98)
				.accessibilityLabel(Text(.About.iconAccessibility(ApplicationInfo.applicationName())))
				.padding(.bottom, 14)

			Text(verbatim: ApplicationInfo.applicationName())
				.font(.headline)
				.textSelection(.enabled)

			Text(verbatim: Self.versionDescription(
				version: ApplicationInfo.applicationVersionShort(),
				build: ApplicationInfo.applicationVersion()
			))
			.font(.caption)
			.textSelection(.enabled)
			.padding(.top, 4)

			if copyright.isEmpty == false {
				Text(verbatim: copyright)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.textSelection(.enabled)
					.padding(.top, 6)
			}

			Button(action: openAcknowledgements) {
				Text(.About.acknowledgementsButton)
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

	/// The application name is drawn above this, so the line under it says what
	/// version that name is at rather than repeating the name.
	static func versionDescription(version: String, build: String) -> String {
		guard build.isEmpty == false, build != version else {
			return String(localized: .About.applicationVersion(version))
		}

		return String(localized: .About.applicationVersionWithBuild(version, build))
	}
}
