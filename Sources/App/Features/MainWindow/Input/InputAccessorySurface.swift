// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/** The surface everything set above the message field is drawn on: the reply
 banner, the questions, the row about questions elsewhere and the command list.

 Flat material, never glass, because the capsule below is the glass and glass
 does not sit on glass. The material turns opaque by itself under Reduce
 Transparency; under Increase Contrast it gains the separator edge the system
 gives its own bars, which the material alone does not draw. */
struct InputAccessorySurface: ViewModifier {
	@Environment(\.colorSchemeContrast) private var contrast

	func body(content: Content) -> some View {
		let shape = RoundedRectangle(cornerRadius: InputBarLayout.accessoryCornerRadius)
		content
			.background(.regularMaterial, in: shape)
			.overlay {
				if contrast == .increased {
					shape
						.strokeBorder(Color(nsColor: .separatorColor))
						.accessibilityHidden(true)
				}
			}
	}
}

extension View {
	/// Draws the view on the surface set above the message field.
	func inputAccessorySurface() -> some View {
		modifier(InputAccessorySurface())
	}
}
