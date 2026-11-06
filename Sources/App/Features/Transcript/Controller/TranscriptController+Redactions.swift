// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension TranscriptController {
	/** A message in this conversation was deleted.

	 The deletion is remembered first, so every row drawn from now on is checked
	 against it; the stored line is overwritten; and a row already on screen is
	 replaced in place. A view still replaying history draws the placeholder
	 when the row arrives, and finds it again when the replay finishes. */
	func noteRedaction(ofMessageIdentifier identifier: String) {
		guard !terminating, identifier.isEmpty == false else { return }
		redactions.record(identifier)
		if let associatedItem {
			scrollback.redactMessage(withIdentifier: identifier, inView: associatedItem.uniqueIdentifier)
		}
		guard transcriptProjection.phase == .active else { return }
		enqueueMainActorWork { [weak self] in
			guard let self else { return }
			backingView?.redactMessage(withIdentifier: identifier, placeholder: Self.redactionPlaceholder)
		}
	}

	static var redactionPlaceholder: String {
		String(localized: .Transcript.messageDeleted)
	}

	/// Replaces every row of a deleted message the view already holds, after a
	/// replay that may have drawn them from storage.
	func restoreRedactions() {
		for identifier in redactions.all {
			backingView?.redactMessage(withIdentifier: identifier.rawValue, placeholder: Self.redactionPlaceholder)
		}
	}
}
