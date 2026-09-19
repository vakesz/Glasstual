// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Alert suppression", .serialized)
struct AlertSuppressionTests {
	/// The suppression family is catalogued as a container key, so the flags are
	/// stored there rather than in UserDefaults.standard, which is what makes an
	/// imported "do not ask again" take effect.
	@Test("An alert is suppressed exactly when its stored preference says so")
	func alertSuppressionDecisionFollowsTheStoredPreference() {
		let baseKey = "AppKitSupportTests.\(UUID().uuidString)"
		let defaultsKey = AlertSuppression.suppressionKey(withBase: baseKey)
		let defaults = GlasstualUserDefaults.container
		defer { defaults.removeObject(forKey: defaultsKey) }

		#expect(AlertSuppression.isSuppressed(baseKey: baseKey) == false)

		defaults.set(true, forKey: defaultsKey)

		#expect(AlertSuppression.isSuppressed(baseKey: baseKey))
	}
}
