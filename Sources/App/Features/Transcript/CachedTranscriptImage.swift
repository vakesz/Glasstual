// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

struct CachedTranscriptImage {
	let linkIdentifier: String
	/// Where the image came from, so its run can offer the link it stands for.
	let sourceURL: URL
	let image: NSImage
	let originalSize: NSSize
	let attachment: NSTextAttachment
}
