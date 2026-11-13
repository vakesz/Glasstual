// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
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
	static let topicSideInset = UISpacing.comfortable

	/// Between the topic and the chevron that unfolds it, and above and below
	/// the topic inside its bar.
	static let topicGap = UISpacing.regular

	/// The square the topic's chevron is clickable in. The glyph inside it is
	/// a sidebar glyph's width; the target around it is what a pointer has to
	/// be able to hit.
	static let topicDisclosureHitTarget: CGFloat = 24

	/** The transcript's top content inset: the safe area the toolbar covers,
	 plus the topic bar where one is shown. The topic bar carries its own gap
	 above and below the topic, so nothing is added for it here. */
	static func topContentInset(safeAreaTop: CGFloat, topicBarHeight: CGFloat?) -> CGFloat {
		max(0, safeAreaTop) + max(0, topicBarHeight ?? 0)
	}

	/** Whether the strip behind the toolbar draws a hairline at its foot.

	 The topic bar draws that edge under itself, so the strip draws it only
	 while no topic bar is shown, and only where there is a toolbar to be
	 under: a transcript with no safe area above it has no strip. */
	static func showsToolbarSeparator(safeAreaTop: CGFloat, topicBarIsShown: Bool) -> Bool {
		safeAreaTop > 0 && topicBarIsShown == false
	}

	/// How close to the top of the document the reader has to scroll before
	/// the next page of history is fetched.
	static let historyFetchTrigger: CGFloat = 160

	/// How near the end of the document still counts as being at the end. It
	/// is measured against the part of the clip view the input bar does not
	/// cover, so it only has to absorb one line's worth of growth.
	static let followBottomSlack: CGFloat = 40

	/// The largest an inline image is drawn.
	static let inlineImageBox = CGSize(width: 480, height: 320)

	/** The box a placeholder for an image that waits for the reader is drawn
	 in, at most. It is far shorter than most pictures, so the image that
	 replaces it moves the lines below by less than an image added outright. */
	static let inlineImagePlaceholderBox = CGSize(width: 320, height: 44)
	static let inlineImagePlaceholderPadding: CGFloat = 12
	static let inlineImagePlaceholderSpacing: CGFloat = 8

	/// What an inline image keeps clear of the column's trailing edge, so a
	/// picture never runs under the scroller.
	static let inlineImageSideInset: CGFloat = 40

	/** The widest an inline image is drawn in a text view `width` points wide.

	 A text view that has not been laid out yet reports no width. That is not a
	 column of no width: the picture is drawn at the box's width, and drawn
	 again at the width the column turns out to have. */
	static func inlineImageMaximumWidth(forTextViewWidth width: CGFloat) -> CGFloat {
		guard width > 0 else { return inlineImageBox.width }
		let available = max(0, width - inlineImageSideInset)
		return max(min(inlineImageBox.width, available), min(available, 120))
	}

	/// One paragraph style for transcript lines, shared by the document and
	/// the fold summaries so spacing cannot drift between them.
	static func transcriptParagraph(lineSpacing: CGFloat, messageSpacing: CGFloat, horizontalPadding: CGFloat) -> NSMutableParagraphStyle {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = lineSpacing
		paragraph.paragraphSpacing = messageSpacing
		paragraph.firstLineHeadIndent = horizontalPadding
		paragraph.headIndent = horizontalPadding
		paragraph.tailIndent = -horizontalPadding
		return paragraph
	}
}
