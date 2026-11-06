// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** "Do not ask again" on the open-link alert answers for one scheme only:
 consent to hand an `ftp:` link to another application is not consent for
 `irc:`, and the shipped allowlist does not offer the schemes that start a
 remote shell. */
@MainActor
@Suite("Transcript link consent", .serialized)
struct TranscriptLinkConsentTests {
	@Test("Each scheme records its own suppression")
	func schemesAreRecordedSeparately() {
		let ftp = TranscriptContextMenuSuppressionKey.openExternalURL(scheme: "ftp")
		let irc = TranscriptContextMenuSuppressionKey.openExternalURL(scheme: "irc")
		let defaults = GlasstualUserDefaults.container
		defer {
			for key in [ftp, irc] {
				let full = AlertSuppression.suppressionKey(withBase: key)
				defaults.removeObject(forKey: full)
				defaults.removeObject(forKey: full + " -> Response")
			}
		}

		#expect(ftp != irc)

		AlertSuppression.record(.alternate, fullKey: AlertSuppression.suppressionKey(withBase: ftp))

		#expect(AlertSuppression.isSuppressed(baseKey: ftp))
		#expect(AlertSuppression.suppressedResponse(baseKey: ftp) == .alternate)
		#expect(AlertSuppression.isSuppressed(baseKey: irc) == false)
	}

	@Test("A scheme's case does not change its key")
	func schemeCaseIsIgnored() {
		#expect(
			TranscriptContextMenuSuppressionKey.openExternalURL(scheme: "FTP")
				== TranscriptContextMenuSuppressionKey.openExternalURL(scheme: "ftp")
		)
	}

	@Test("Schemes that start a remote shell or a man page are not allowed by default",
	      arguments: ["ssh", "telnet", "x-man-page"])
	func riskySchemesAreNotDefaults(scheme: String) {
		#expect(SettingsKeys.LinkSchemes.permittedDefault.defaultValue.contains(scheme) == false)
	}
}
