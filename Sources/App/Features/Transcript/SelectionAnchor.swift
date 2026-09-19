// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Both UTF-16 endpoints are relative to a semantic segment within a stable row.
struct SelectionAnchor: Equatable {
	struct Endpoint: Equatable {
		let lineNumber: String
		let segment: String?
		let offset: Int
	}

	let start: Endpoint
	let end: Endpoint
}
