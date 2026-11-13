// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/** Whether the system asks an interface to drop its animations.

 SwiftUI views read `\.accessibilityReduceMotion` from the environment; this is
 the same setting for the AppKit side and for the observable models a view is
 driven by, neither of which can reach an environment. One accessor, so a
 feature cannot answer the question two ways and honour the setting in only one
 of them. */
@MainActor
enum ReduceMotion {
	static var isEnabled: Bool {
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
	}

	/// `animation`, unless the system asked for stillness.
	static func animation(_ animation: Animation) -> Animation? {
		isEnabled ? nil : animation
	}
}
