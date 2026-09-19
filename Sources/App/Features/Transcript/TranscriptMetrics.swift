// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

/** What the transcript is spaced and sized by.

 The window's own scale (`UISpacing`) answers most of it, and
 the few numbers that belong to this view alone are named here rather than
 written into a constraint where nobody can tell a deliberate value from a
 number somebody typed. */
enum TranscriptMetrics {
	/// Above and below the document, so the first and last line are not flush
	/// against the topic bar or the input capsule.
	static let documentInset = UISpacing.regular

	/// The topic bar's side margin. It matches the transcript theme's default
	/// horizontal padding, so the topic starts where the messages start.
	static let topicSideInset: CGFloat = 10

	/// Between the topic and the chevron that unfolds it, and between the
	/// topic bar and the first line of the transcript.
	static let topicGap = UISpacing.regular

	/// The square the topic's chevron is clickable in. The glyph inside it is
	/// a sidebar glyph's width; the target around it is what a pointer has to
	/// be able to hit.
	static let topicDisclosureHitTarget: CGFloat = 24

	/// The circle the reader is taken back to the newest line by, sized to a
	/// sidebar row's natural height so that it reads as part of the window's
	/// scale rather than as a number chosen for this one control.
	static let jumpToLatestButtonSize: CGFloat = 28

	/// How close to the top of the document the reader has to scroll before
	/// the next page of history is fetched.
	static let historyFetchTrigger: CGFloat = 160

	/// How near the end of the document still counts as being at the end. It
	/// is measured against the part of the clip view the input bar does not
	/// cover, so it only has to absorb one line's worth of growth.
	static let followBottomSlack: CGFloat = 40

	/// The largest an inline image is drawn.
	static let inlineImageBox = CGSize(width: 480, height: 320)

	/// What an inline image keeps clear of the column's trailing edge, so a
	/// picture never runs under the scroller.
	static let inlineImageSideInset: CGFloat = 40
}
