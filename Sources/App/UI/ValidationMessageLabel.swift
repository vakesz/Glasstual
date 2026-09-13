/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/** The one way the connection, channel and address-book sheets say that a
 field cannot be saved.

 Four presentations used to be in use at once — a red rounded border, a popover
 the model had to remember to open, a caption under a row, and a modal alert —
 so one kind of mistake looked like a different kind of problem depending on
 which sheet the person happened to be in. This is the Address Book sheet's
 presentation: it stays beside the field it is about, and VoiceOver reads it as
 part of that field's group.

 It has no feature owner -- the connection, channel, address-book, highlight
 and onboarding sheets all draw it -- so it lives beside the other shared
 controls. */
struct ValidationMessageLabel: View {
	private let message: String

	init(_ message: String) {
		self.message = message
	}

	var body: some View {
		Label(message, systemImage: "exclamationmark.circle.fill")
			.font(.caption)
			.foregroundStyle(.red)
			.accessibilityLabel(message)
	}
}
