// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// A form row whose complaint is shown under the control it belongs to, rather
/// than in an alert after the fact.
struct ValidatedFormRow<Content: View>: View {
	let label: String
	let problem: String?
	@ViewBuilder let content: Content

	var body: some View {
		LabeledContent(label) {
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				content
					.labelsHidden()
				if let problem {
					ValidationMessageLabel(problem)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		.accessibilityElement(children: .contain)
	}
}
