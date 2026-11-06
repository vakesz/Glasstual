// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

struct CompletionSession {
	var request: CompletionRequest
	var currentText: String
	var selectionAfterCompletion: NSRange?
	var selectedCandidateIndex: Int?

	func canContinue(text: String, selection: NSRange) -> Bool {
		selectedCandidateIndex != nil &&
			selectionAfterCompletion == selection &&
			currentText.isEmpty == false &&
			currentText == text
	}

	mutating func selectCandidate(count: Int, movingForward: Bool) -> Int {
		let selectedIndex: Int = if let previous = selectedCandidateIndex, previous < count {
			if movingForward {
				(previous + 1) % count
			} else {
				previous == 0 ? count - 1 : previous - 1
			}
		} else {
			0
		}

		selectedCandidateIndex = selectedIndex
		return selectedIndex
	}
}
