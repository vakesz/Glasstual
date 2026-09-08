/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/** The layout fragment for a paragraph that carries a separator: the unread
 hairline, or the rule above the current-session caption. It draws the
 paragraph as TextKit 2 would and adds the rule, `ruleInset` points below the
 paragraph's top, across the container's width.

 This is where TextKit 2 puts a paragraph's decoration. The alternative, an
 `NSTextBlock` border in the paragraph style, is a TextKit 1 feature, and a
 text view whose storage holds one is silently moved back to TextKit 1. */
final nonisolated class TranscriptRuleLayoutFragment: NSTextLayoutFragment { // nonisolated: immutable
	let ruleColor: NSColor
	let ruleInset: CGFloat

	init(textElement: NSTextElement, range: NSTextRange?, ruleColor: NSColor, ruleInset: CGFloat) {
		self.ruleColor = ruleColor
		self.ruleInset = ruleInset
		super.init(textElement: textElement, range: range)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("TranscriptRuleLayoutFragment is not archived")
	}

	/** Where the rule goes, relative to the fragment's origin. The fragment's
	 own frame is only what its centred text used -- nothing at all for the
	 unread marker's zero-width glyph -- so the rule is measured from the
	 container's edges instead, the way the old text block's border was. */
	private var ruleBounds: CGRect {
		let container = textLayoutManager?.textContainer
		let padding = container?.lineFragmentPadding ?? 0
		let width = (container?.size.width ?? layoutFragmentFrame.width) - padding * 2
		return CGRect(x: padding - layoutFragmentFrame.minX, y: ruleInset, width: max(0, width), height: 1)
	}

	/// The surface has to cover the rule, which lies outside the text's own
	/// bounds on both sides and, for the marker paragraph, below its glyph.
	override var renderingSurfaceBounds: CGRect {
		super.renderingSurfaceBounds.union(ruleBounds)
	}

	override func draw(at point: CGPoint, in context: CGContext) {
		super.draw(at: point, in: context)
		let rule = ruleBounds
		guard rule.width > 0 else { return }
		context.saveGState()
		context.setFillColor(ruleColor.cgColor)
		context.fill(rule.offsetBy(dx: point.x, dy: point.y))
		context.restoreGState()
	}
}
