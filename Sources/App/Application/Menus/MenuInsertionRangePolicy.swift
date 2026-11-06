// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/// Where the nickname insertion above landed once it has replaced a selection.
/// The replaced range describes storage that no longer exists, so nothing may
/// be measured against it afterwards.
nonisolated enum MenuInsertionRangePolicy {
	static func insertedRange(replacing replaced: NSRange, with insertion: String) -> NSRange {
		NSRange(location: replaced.location, length: insertion.utf16.count)
	}
}
