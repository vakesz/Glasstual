// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What the transcript is showing, as the controller reads it: the oldest and
/// newest lines on screen, how many there are, and how many more the buffer
/// takes before it trims.
struct TranscriptDisplayedBounds: Equatable {
	let oldest: String?
	let newest: String?
	let count: Int
	let remainingCapacity: Int
}
