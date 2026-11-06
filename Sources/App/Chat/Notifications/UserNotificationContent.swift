// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What one notification says.

 The title is who or what it is about, the subtitle is where it happened and
 the body is the detail. Every event fills the title; the rest is what it has. */
struct UserNotificationContent {
	var title: String
	var subtitle: String?
	var body: String?
}
