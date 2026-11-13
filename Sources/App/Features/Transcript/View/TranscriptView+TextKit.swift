// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension TranscriptView {
	/** Hands a marker paragraph the fragment that draws its rule. Pure: the
	 answer comes from the paragraph's own attributes, and nothing of the
	 view is read. */
	nonisolated func textLayoutManager( // nonisolated: pure
		_: NSTextLayoutManager,
		textLayoutFragmentFor _: any NSTextLocation,
		in textElement: NSTextElement
	) -> NSTextLayoutFragment {
		guard let paragraph = textElement as? NSTextParagraph,
		      paragraph.attributedString.length > 0,
		      let color = paragraph.attributedString.attribute(.transcriptRuleColor, at: 0, effectiveRange: nil)
		      as? NSColor
		else {
			return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
		}
		let inset = (paragraph.attributedString.attribute(.transcriptRuleInset, at: 0, effectiveRange: nil)
			as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
		return TranscriptRuleLayoutFragment(
			textElement: textElement,
			range: textElement.elementRange,
			ruleColor: color,
			ruleInset: inset
		)
	}
}

extension TranscriptView: NSPopoverDelegate {
	func popoverDidClose(_ notification: Notification) {
		if notification.object as? NSPopover === memberInformationPopover {
			memberInformationPopover = nil
		}
	}
}
