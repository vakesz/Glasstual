// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** The bar above the transcript: the channel's topic as it reads, the channel's
 modes as a caption after it, and the chevron that unfolds a topic one line
 cannot hold.

 It shares nothing with the transcript below it — its own text, its own menu,
 its own layout — so it owns all of them, and the transcript hands it the topic
 and asks the two questions only the conversation can answer: whether this
 reader may set the topic, and what to do when they ask to. */
@MainActor
final class TranscriptTopicBar: NSView {
	/// Unfolded, the topic still stops short of taking the transcript's room:
	/// the longest topic a server allows wraps to about this many lines at the
	/// column's minimum width, and anything beyond it is in the tooltip.
	static let expandedTopicLineLimit = 8

	/// Whether the channel lets this reader set the topic, which is what the
	/// double click and the menu item are validated against.
	var canModifyTopic: (@MainActor () -> Bool)?
	/// The reader asked to set the topic, by double click or from the menu.
	var onModifyTopic: (@MainActor () -> Void)?
	var onOpenLink: (@MainActor (URL) -> Void)?

	private(set) var label = TopicLabel(wrappingLabelWithString: "")
	/** SwiftUI owns controls; this adapter only hosts one. */
	private(set) var disclosure = NSHostingView(rootView: TopicDisclosureButton(isExpanded: false, action: {}))

	/** The topic as the wire carries it, control codes and all.

	 The label holds the rendered text, so it is not something the topic can be
	 drawn from a second time: re-rendering from the label dropped every colour
	 and bold the topic carried the moment the theme or the text size moved. */
	private var topicText = ""
	private var modeCaption: String?
	private var isExpanded = false
	private var textScale: CGFloat = 1
	private var lineHeightCache: (font: NSFont, height: CGFloat)?

	init() {
		super.init(frame: .zero)
		translatesAutoresizingMaskIntoConstraints = false
		configure()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// Whether the bar draws anything at all. A view with no topic and no modes
	/// gives its room back to the transcript.
	var isEmpty: Bool {
		label.attributedStringValue.length == 0
	}

	/// The topic without its control codes, which is what a reader who asks for
	/// it expects to paste.
	var copyableTopic: String {
		attributedTopic(topicText).string
	}

	/** Takes the topic the conversation is on now.

	 An unfolded bar folds again: the new topic is a different length, and the
	 reader unfolded the one before it. */
	func setTopic(_ topic: String?, modes: String?) {
		topicText = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if isExpanded {
			isExpanded = false
			applyExpansion()
		}
		refresh(modes: modes)
	}

	/** Draws the bar from the topic it was last given and the channel's modes.

	 The modes follow the topic as a caption because the window subtitle no
	 longer carries them, and the bar is where the rest of the conversation's
	 context already is. They are not part of the topic: what the tooltip shows
	 and what Copy Topic puts on the pasteboard is the topic alone, which is
	 what somebody actually set. */
	func refresh(modes: String?) {
		modeCaption = modes
		let topic = attributedTopic(topicText)
		let displayed = NSMutableAttributedString()
		/* Isolated, so the topic's own direction cannot carry the caption after
		 it along. */
		TranscriptTextSanitizer.appendIsolated(
			topic,
			to: displayed,
			isolateAttributes: topic.length > 0 ? topic.attributes(at: 0, effectiveRange: nil) : [:]
		)
		if let modes {
			/* The gap carries the caption's own attributes: an unstyled run
			 between them would be drawn in the system default rather than in
			 the theme, which in a dark transcript is black on black. */
			displayed.append(attributedTopicCaption(displayed.length > 0 ? "\u{2003}\(modes)" : modes))
		}
		label.attributedStringValue = displayed
		label.toolTip = topicText.isEmpty ? nil : topic.string
		needsLayout = true
	}

	/// The topic follows ⌘= and ⌘− with the transcript: it is text in the same
	/// window, and a reader who needs the messages larger needs the topic larger
	/// too. The label caches its intrinsic height, so the cache goes with it.
	func setTextScale(_ scale: CGFloat) {
		textScale = scale
		refresh(modes: modeCaption)
		label.invalidateIntrinsicContentSize()
		lineHeightCache = nil
		needsLayout = true
	}

	override func layout() {
		super.layout()
		updateWrappingWidth()
		updateDisclosure()
	}

	// MARK: - Construction

	private func configure() {
		label.isSelectable = true
		label.onOpenLink = { [weak self] in self?.onOpenLink?($0) }
		label.translatesAutoresizingMaskIntoConstraints = false
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let topicClick = NSClickGestureRecognizer(target: self, action: #selector(topicDoubleClicked(_:)))
		topicClick.numberOfClicksRequired = 2
		label.addGestureRecognizer(topicClick)
		label.menu = makeMenu()

		/* The topic stays on one line and the chevron unfolds it. A click on the
		 text itself cannot do that: the field is selectable so its links open
		 and its words copy, and a single click there has to keep meaning that. */
		disclosure.sizingOptions = .intrinsicContentSize
		disclosure.translatesAutoresizingMaskIntoConstraints = false
		disclosure.setContentHuggingPriority(.required, for: .horizontal)
		disclosure.setContentCompressionResistancePriority(.required, for: .horizontal)
		applyExpansion()

		addSubview(label)
		addSubview(disclosure)
		NSLayoutConstraint.activate([
			label.topAnchor.constraint(equalTo: topAnchor, constant: TranscriptMetrics.topicGap),
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TranscriptMetrics.topicSideInset),
			label.bottomAnchor.constraint(equalTo: bottomAnchor),
			label.trailingAnchor.constraint(
				equalTo: disclosure.leadingAnchor,
				constant: -TranscriptMetrics.topicGap
			),
			disclosure.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -TranscriptMetrics.topicSideInset
			),
			disclosure.topAnchor.constraint(equalTo: label.topAnchor),
		])
	}

	/** The topic bar's own menu.

	 A right click on the topic used to fall through to the transcript's, which
	 offered the conversation's commands for text that is not part of it. */
	private func makeMenu() -> NSMenu {
		let menu = NSMenu()
		let copy = NSMenuItem(
			title: String(localized: .Transcript.copyTopic),
			action: #selector(copyTopicMenuItemClicked(_:)),
			keyEquivalent: ""
		)
		copy.target = self
		menu.addItem(copy)
		let change = NSMenuItem(
			title: String(localized: .Transcript.menuChannelModifyTopic),
			action: #selector(changeTopicMenuItemClicked(_:)),
			keyEquivalent: ""
		)
		change.target = self
		menu.addItem(change)
		return menu
	}

	// MARK: - Commands

	@objc private func topicDoubleClicked(_: NSClickGestureRecognizer) {
		guard canModifyTopic?() == true else { return }
		onModifyTopic?()
	}

	@objc private func changeTopicMenuItemClicked(_: NSMenuItem) {
		onModifyTopic?()
	}

	/// Copies the topic as it reads. Not what the bar draws: the mode caption
	/// after it is the bar's own context, and nobody set it as the topic.
	@objc private func copyTopicMenuItemClicked(_: NSMenuItem) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(copyableTopic, forType: .string)
	}

	// MARK: - Folding

	private func toggleExpansion() {
		isExpanded.toggle()
		applyExpansion()
	}

	/** Folded, the topic is one truncated line; unfolded it wraps in full from
	 its first word, up to `expandedTopicLineLimit` lines. The field caches its
	 intrinsic height, so the cache is dropped here: without that the chevron
	 flipped and the field stayed one line tall until something else moved the
	 layout. */
	private func applyExpansion() {
		/* The field wraps up to the line limit and truncates the last line,
		 in both states; only the limit changes. */
		label.maximumNumberOfLines = isExpanded ? Self.expandedTopicLineLimit : 1
		label.invalidateIntrinsicContentSize()
		disclosure.rootView = TopicDisclosureButton(isExpanded: isExpanded) { [weak self] in
			self?.toggleExpansion()
		}
		needsLayout = true
	}

	/** Tells the field how wide it is, so its intrinsic height is the height of
	 the topic wrapped at that width rather than of one line. A constraint
	 write inside `layout()`, bounded the way the disclosure's is: the width
	 only changes when the frame does, and an unchanged width writes nothing. */
	private func updateWrappingWidth() {
		let width = label.bounds.width
		guard width > 0, label.preferredMaxLayoutWidth != width else { return }
		label.preferredMaxLayoutWidth = width
		label.invalidateIntrinsicContentSize()
	}

	/// The chevron is only offered when one line does not hold the topic.
	private func updateDisclosure() {
		let text = label.attributedStringValue
		guard isHidden == false, let font = topicFont(of: text), label.bounds.width > 0 else {
			setDisclosureHidden(true)
			return
		}
		let fullHeight = text.boundingRect(
			with: NSSize(width: label.bounds.width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		/* Half a line of slack: a topic that fits on one line still measures a
		 fraction over it once the font's leading is counted, and a chevron
		 offered on a topic with nothing to unfold is a chevron that does
		 nothing. */
		let overflows = fullHeight > topicLineHeight(for: font) * 1.5
		setDisclosureHidden(overflows == false)
		/* Also a constraint write from inside `layout()`, and bounded the same
		 way: the flag flips first, so the next pass finds nothing to fold. */
		if overflows == false, isExpanded {
			isExpanded = false
			applyExpansion()
		}
	}

	/// Runs from `layout()`, so a write that changes nothing must not ask for
	/// another constraint pass.
	private func setDisclosureHidden(_ hidden: Bool) {
		guard disclosure.isHidden != hidden else { return }
		disclosure.isHidden = hidden
	}

	/** The font the topic is actually drawn in.

	 ``attributedTopic(_:)`` scales the body size by the reader's text zoom and
	 writes the result into the string, which the field's own `font` never
	 learns: measuring the scaled string against an unscaled line height made
	 every one-line topic overflow at ⌘=, and the chevron appeared on a topic
	 with nothing to unfold. */
	private func topicFont(of text: NSAttributedString) -> NSFont? {
		guard text.length > 0 else { return label.font }
		return text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? label.font
	}

	/// Asked on every layout pass, so the measurement is kept per font.
	private func topicLineHeight(for font: NSFont) -> CGFloat {
		if let lineHeightCache, lineHeightCache.font == font {
			return lineHeightCache.height
		}
		let height = TextLineMetrics.lineHeight(for: font)
		lineHeightCache = (font, height)
		return height
	}

	// MARK: - Drawing

	private func attributedTopic(_ topic: String) -> NSAttributedString {
		let palette = AppServices.theme.theme.palette
		/* The topic is context, not conversation: secondary text at the body
		 size, with only its links in the link colour. */
		let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
		let font = NSFont.systemFont(ofSize: bodySize * textScale)
		let secondary = AppServices.theme.resolved(palette.secondaryText)
		/* A topic is wire text: it carries the same control codes a message
		 does, and drawing the string as it arrived put the codes themselves in
		 the bar, in its tooltip and on the pasteboard. */
		let result = (topic as NSString).attributedString(
			withIRCFormatting: font,
			preferredFontColor: secondary,
			honorFormattingSetting: true
		).map(NSMutableAttributedString.init(attributedString:))
			?? NSMutableAttributedString(string: topic, attributes: [
				.font: font,
				.foregroundColor: secondary,
			])
		/* Anybody allowed to set the topic can put a line break or a reversal
		 in it; the bar is one line of text, in the reading order it is given. */
		TranscriptTextSanitizer.sanitize(result)
		/* The links are located in the text as drawn: a scan of the wire form
		 counts the control codes too, and every range after the first one is
		 then a few characters out. */
		for link in LinkParser.locateLinks(in: result.string)
			where LinkParser.isPermittedLink(link.stringValue)
		{
			guard let url = URL(string: link.stringValue), NSMaxRange(link.range) <= result.length else {
				continue
			}
			result.addAttributes([
				.link: url,
				.foregroundColor: AppServices.theme.resolved(palette.link),
				.underlineStyle: NSUnderlineStyle.single.rawValue,
			], range: link.range)
		}
		return result
	}

	/** The caption the topic bar draws after the topic: the channel's modes.

	 Dimmer than the topic and a shade smaller, because it is the bar's own
	 context rather than text anybody wrote. */
	private func attributedTopicCaption(_ caption: String) -> NSAttributedString {
		let palette = AppServices.theme.theme.palette
		let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
		return NSAttributedString(string: caption, attributes: [
			.font: NSFont.monospacedDigitSystemFont(ofSize: bodySize * textScale * 0.9, weight: .regular),
			.foregroundColor: AppServices.theme.resolved(palette.timestampText),
		])
	}
}

extension TranscriptTopicBar: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(changeTopicMenuItemClicked(_:)): canModifyTopic?() == true
		case #selector(copyTopicMenuItemClicked(_:)): isEmpty == false
		default: true
		}
	}
}

/** The topic label. Its intrinsic width is withheld from Auto Layout: a
 wrapping label reports the whole topic on one line as its natural width, and
 through the transcript's fitting size that became the column's minimum, so
 the window grew to the topic's length on every corner drag. The height still
 comes from the label, wrapped at `preferredMaxLayoutWidth`. */
final class TopicLabel: NSTextView, NSTextViewDelegate {
	var onOpenLink: (@MainActor (URL) -> Void)?
	var maximumNumberOfLines = 1 {
		didSet {
			textContainer?.maximumNumberOfLines = maximumNumberOfLines
			invalidateIntrinsicContentSize()
		}
	}

	var preferredMaxLayoutWidth: CGFloat = 0 {
		didSet {
			guard preferredMaxLayoutWidth > 0 else { return }
			textContainer?.containerSize = NSSize(width: preferredMaxLayoutWidth, height: .greatestFiniteMagnitude)
			invalidateIntrinsicContentSize()
		}
	}

	var attributedStringValue: NSAttributedString {
		get { attributedString() }
		set {
			textStorage?.setAttributedString(newValue)
			invalidateIntrinsicContentSize()
		}
	}

	convenience init(wrappingLabelWithString text: String) {
		self.init(usingTextLayoutManager: true)
		isEditable = false
		isSelectable = true
		isRichText = true
		drawsBackground = false
		textContainerInset = .zero
		textContainer?.lineFragmentPadding = 0
		textContainer?.widthTracksTextView = false
		textContainer?.maximumNumberOfLines = 1
		textContainer?.lineBreakMode = .byTruncatingTail
		delegate = self
		attributedStringValue = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
	}

	override var intrinsicContentSize: NSSize {
		let text = attributedStringValue
		let font = text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
		let lineHeight = TextLineMetrics.lineHeight(for: font ?? NSFont.systemFont(ofSize: 13))
		let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : max(bounds.width, 1)
		let height = text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
		                               options: [.usesLineFragmentOrigin, .usesFontLeading]).height
		return NSSize(
			width: NSView.noIntrinsicMetric,
			height: ceil(max(lineHeight, min(height, lineHeight * CGFloat(maximumNumberOfLines))))
		)
	}

	func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
		let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
		if let url {
			onOpenLink?(url)
		}
		return true
	}

	override func menu(for _: NSEvent) -> NSMenu? {
		menu
	}
}

/// The chevron that folds and unfolds the topic.
struct TopicDisclosureButton: View {
	let isExpanded: Bool
	let action: () -> Void

	private var label: String {
		isExpanded ? AccessibilityStrings.showLessTopic : AccessibilityStrings.showFullTopic
	}

	var body: some View {
		Button(action: action) {
			Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(.secondary)
				/* The glyph is a sidebar glyph's width; what the pointer has to
				 hit is the square around it, which a chevron drawn at its own
				 size is too small to be. */
				.frame(
					width: TranscriptMetrics.topicDisclosureHitTarget,
					height: TranscriptMetrics.topicDisclosureHitTarget
				)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(label)
		.help(label)
	}
}
