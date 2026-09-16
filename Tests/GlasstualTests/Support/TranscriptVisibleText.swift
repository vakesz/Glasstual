/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual

/// Text the reader sees, excluding the renderer's direction isolates and
/// layout padding. Attribute and full-document tests still inspect the source.
func visibleTranscriptText(_ text: NSAttributedString) -> String {
	var result = ""
	text.enumerateAttribute(.transcriptPadding, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
		if value as? Bool != true {
			result += (text.string as NSString).substring(with: range)
		}
	}
	return result
}
