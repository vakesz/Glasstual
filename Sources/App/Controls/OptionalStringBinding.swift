// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

extension Binding where Value == String? {
	/** The optional text as a field's text.

	 A configuration says "nothing was entered" with `nil`, while a `TextField`
	 says it with an empty string. Every sheet that edits an optional string
	 needs that one translation, so it is written here rather than as a
	 pass-through property on each model. */
	var orEmpty: Binding<String> {
		Binding<String>(
			get: { wrappedValue ?? "" },
			set: { wrappedValue = $0.isEmpty ? nil : $0 }
		)
	}
}
