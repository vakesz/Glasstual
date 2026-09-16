/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import Foundation
import SwiftUI

/** The bar above the transcript: the channel's topic as it reads, the channel's
 modes as a caption after it, and the chevron that unfolds a topic one line
 cannot hold. */
extension TranscriptView {
	/** Takes the topic the conversation is on now.

	 An unfolded bar folds again: the new topic is a different length, and the
	 reader unfolded the one before it. */
	func setTopic(_ topic: String?) {
		topicText = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if isTopicExpanded {
			isTopicExpanded = false
			applyTopicExpansion()
		}
		refreshTopicBar()
	}

	/** Draws the bar from the topic it was last given and the channel's modes.

	 The modes follow the topic as a caption because the window subtitle no
	 longer carries them, and the bar is where the rest of the conversation's
	 context already is. They are not part of the topic: what the tooltip shows
	 and what Copy Topic puts on the pasteboard is the topic alone, which is
	 what somebody actually set. */
	func refreshTopicBar() {
		let topic = attributedTopic(topicText)
		let displayed = NSMutableAttributedString()
		/* Isolated, so the topic's own direction cannot carry the caption after
		 it along. */
		appendIsolated(
			topic,
			to: displayed,
			isolateAttributes: topic.length > 0 ? topic.attributes(at: 0, effectiveRange: nil) : [:]
		)
		if let modes = channelModeCaption {
			/* The gap carries the caption's own attributes: an unstyled run
			 between them would be drawn in the system default rather than in
			 the theme, which in a dark transcript is black on black. */
			displayed.append(attributedTopicCaption(displayed.length > 0 ? "\u{2003}\(modes)" : modes))
		}
		topicField.attributedStringValue = displayed
		topicField.toolTip = topicText.isEmpty ? nil : topic.string
		topicField.isHidden = displayed.length == 0
		if topicField.isHidden {
			scrollViewTopWithTopicConstraint?.isActive = false
			scrollViewTopWithoutTopicConstraint?.isActive = true
		} else {
			scrollViewTopWithoutTopicConstraint?.isActive = false
			scrollViewTopWithTopicConstraint?.isActive = true
		}
		needsLayout = true
	}

	/// The channel's modes as the caption spells them, with any key masked, or
	/// nothing where the view is not a channel or has no modes yet.
	private var channelModeCaption: String? {
		guard let modes = viewController?.associatedChannel?.modeInfo?.stringWithMaskedPassword,
		      modes.isEmpty == false
		else { return nil }
		return modes
	}

	@objc func topicDoubleClicked(_: NSClickGestureRecognizer) {
		guard canModifyTopic else { return }
		policy.topicBarDoubleClicked()
	}

	@objc func changeTopicMenuItemClicked(_: NSMenuItem) {
		policy.topicBarDoubleClicked()
	}

	/// Copies the topic as it reads. Not what the bar draws: the mode caption
	/// after it is the bar's own context, and nobody set it as the topic.
	@objc func copyTopicMenuItemClicked(_: NSMenuItem) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(copyableTopic, forType: .string)
	}

	/// The topic without its control codes, which is what a reader who asks for
	/// it expects to paste.
	var copyableTopic: String {
		attributedTopic(topicText).string
	}

	/// Whether the channel lets this reader set the topic: either it is not
	/// restricted to operators, or they are one.
	var canModifyTopic: Bool {
		guard let channel = viewController?.associatedChannel, channel.isChannel else { return false }
		guard channel.modeInfo?.modes.modeInfo(for: ChannelMode.operatorTopic.rawValue)?.modeIsSet == true
		else { return true }
		guard let nickname = viewController?.associatedClient?.userNickname,
		      let member = channel.findMember(nickname)
		else { return false }
		return member.isOp || member.isHalfOp
	}

	/** The topic bar's own menu.

	 A right click on the topic used to fall through to the transcript's, which
	 offered the conversation's commands for text that is not part of it. */
	func topicMenu() -> NSMenu {
		let menu = NSMenu()
		let copy = NSMenuItem(
			title: TranscriptViewStrings.copyTopic,
			action: #selector(copyTopicMenuItemClicked(_:)),
			keyEquivalent: ""
		)
		copy.target = self
		menu.addItem(copy)
		let change = NSMenuItem(
			title: MenuStrings.Channel.modifyTopic,
			action: #selector(changeTopicMenuItemClicked(_:)),
			keyEquivalent: ""
		)
		change.target = self
		menu.addItem(change)
		return menu
	}

	/// Names the transcript for an assistive reader. Without it the text view
	/// is announced as an unlabelled document, in a window full of them.
	func updateAccessibilityDescription() {
		let name = viewController?.associatedChannel?.name
			?? viewController?.associatedClient?.networkNameAlt ?? ""
		textView.setAccessibilityLabel(TranscriptViewStrings.transcriptAccessibility(conversation: name))
		textView.setAccessibilityRoleDescription(TranscriptViewStrings.transcriptRoleDescription)
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

extension TranscriptView {
	func toggleTopicExpansion() {
		isTopicExpanded.toggle()
		applyTopicExpansion()
	}

	/// Unfolded, the topic still stops short of taking the transcript's room:
	/// the longest topic a server allows wraps to about this many lines at the
	/// column's minimum width, and anything beyond it is in the tooltip.
	static let expandedTopicLineLimit = 8

	/** Folded, the topic is one truncated line; unfolded it wraps in full from
	 its first word, up to `expandedTopicLineLimit` lines. The field caches its intrinsic height, so the cache is
	 dropped here: without that the chevron flipped and the field stayed one
	 line tall until something else moved the layout. */
	func applyTopicExpansion() {
		/* The field wraps up to the line limit and truncates the last line,
		 in both states; only the limit changes. */
		topicField.maximumNumberOfLines = isTopicExpanded ? Self.expandedTopicLineLimit : 1
		topicField.invalidateIntrinsicContentSize()
		topicDisclosure.rootView = TopicDisclosureButton(isExpanded: isTopicExpanded) { [weak self] in
			self?.toggleTopicExpansion()
		}
		needsLayout = true
	}

	/** Tells the field how wide it is, so its intrinsic height is the height of
	 the topic wrapped at that width rather than of one line. A constraint
	 write inside `layout()`, bounded the way the disclosure's is: the width
	 only changes when the frame does, and an unchanged width writes nothing. */
	func updateTopicWrappingWidth() {
		let width = topicField.bounds.width
		guard width > 0, topicField.preferredMaxLayoutWidth != width else { return }
		topicField.preferredMaxLayoutWidth = width
		topicField.invalidateIntrinsicContentSize()
	}

	/// The chevron is only offered when one line does not hold the topic.
	func updateTopicDisclosure() {
		let text = topicField.attributedStringValue
		guard topicField.isHidden == false, let font = topicFont(of: text), topicField.bounds.width > 0 else {
			setTopicDisclosureHidden(true)
			return
		}
		let fullHeight = text.boundingRect(
			with: NSSize(width: topicField.bounds.width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		/* Half a line of slack: a topic that fits on one line still measures a
		 fraction over it once the font's leading is counted, and a chevron
		 offered on a topic with nothing to unfold is a chevron that does
		 nothing. */
		let overflows = fullHeight > topicLineHeight(for: font) * 1.5
		setTopicDisclosureHidden(overflows == false)
		/* Also a constraint write from inside `layout()`, and bounded the same
		 way: the flag flips first, so the next pass finds nothing to fold. */
		if overflows == false, isTopicExpanded {
			isTopicExpanded = false
			applyTopicExpansion()
		}
	}

	/// Runs from `layout()`, so a write that changes nothing must not ask for
	/// another constraint pass.
	private func setTopicDisclosureHidden(_ hidden: Bool) {
		guard topicDisclosure.isHidden != hidden else { return }
		topicDisclosure.isHidden = hidden
	}

	/** The font the topic is actually drawn in.

	 ``attributedTopic(_:)`` scales the body size by the reader's text zoom and
	 writes the result into the string, which the field's own `font` never
	 learns: measuring the scaled string against an unscaled line height made
	 every one-line topic overflow at ⌘=, and the chevron appeared on a topic
	 with nothing to unfold. */
	private func topicFont(of text: NSAttributedString) -> NSFont? {
		guard text.length > 0 else { return topicField.font }
		return text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? topicField.font
	}

	/// Asked on every layout pass, so the measurement is kept per font.
	private func topicLineHeight(for font: NSFont) -> CGFloat {
		if let topicLineHeightCache, topicLineHeightCache.font == font {
			return topicLineHeightCache.height
		}
		let height = TextLineMetrics.lineHeight(for: font)
		topicLineHeightCache = (font, height)
		return height
	}
}

/** The topic label. Its intrinsic width is withheld from Auto Layout: a
 wrapping label reports the whole topic on one line as its natural width, and
 through the transcript's fitting size that became the column's minimum, so
 the window grew to the topic's length on every corner drag. The height still
 comes from the label, wrapped at `preferredMaxLayoutWidth`. */
final class TopicLabel: NSTextField {
	override var intrinsicContentSize: NSSize {
		var size = super.intrinsicContentSize
		size.width = NSView.noIntrinsicMetric
		return size
	}
}
