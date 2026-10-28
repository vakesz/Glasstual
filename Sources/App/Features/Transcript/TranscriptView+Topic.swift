// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension TranscriptView {
	// MARK: - The topic bar

	/// Takes the topic the conversation is on now.
	func setTopic(_ topic: String?) {
		topicBar.setTopic(topic, modes: channelModeCaption)
		showTopicBarIfDrawn()
	}

	/// Redraws the bar from the topic it holds: the modes, the theme or the
	/// reader's text size moved.
	func refreshTopicBar() {
		topicBar.refresh(modes: channelModeCaption)
		showTopicBarIfDrawn()
	}

	/// A bar with neither a topic nor modes to draw gives its room back to the
	/// transcript, which is the only thing outside the bar its content decides.
	func showTopicBarIfDrawn() {
		let hidden = topicBar.isEmpty
		topicBar.isHidden = hidden
		let outgoing = hidden ? scrollViewTopWithTopicConstraint : scrollViewTopWithoutTopicConstraint
		let incoming = hidden ? scrollViewTopWithoutTopicConstraint : scrollViewTopWithTopicConstraint
		outgoing?.isActive = false
		incoming?.isActive = true
		needsLayout = true
	}

	/// The channel's modes as the caption spells them, with any key masked, or
	/// nothing where the view is not a channel or has no modes yet.
	var channelModeCaption: String? {
		guard let modes = viewController?.associatedConversation?.modeInfo?.stringWithMaskedPassword,
		      modes.isEmpty == false
		else { return nil }
		return modes
	}

	/// Whether the channel lets this reader set the topic: either it is not
	/// restricted to operators, or they are one.
	var canModifyTopic: Bool {
		ChannelActionPermissions(
			channel: viewController?.associatedConversation,
			session: viewController?.associatedSession
		).canModifyTopic
	}

	/// Names the transcript for an assistive reader. Without it the text view
	/// is announced as an unlabelled document, in a window full of them.
	func updateAccessibilityDescription() {
		let name = viewController?.associatedConversation?.name
			?? viewController?.associatedSession?.networkNameAlt ?? ""
		textView.setAccessibilityLabel(String(localized: .Transcript.transcriptAccessibility(name)))
		textView.setAccessibilityRoleDescription(String(localized: .Transcript.transcriptRole))
	}

	/** Shows the profile of a nickname the reader clicked in the transcript,
	 anchored to the text that named them. Only someone in the conversation has
	 a profile to show: a name that has since left is left alone. */
	func showMemberInformation(for nickname: String, relativeTo rect: NSRect, of view: NSView) {
		closeMemberInformation()
		guard let member = viewController?.associatedConversation?.findMember(nickname) else { return }
		let popover = NSPopover()
		popover.behavior = .transient
		popover.delegate = self
		popover.contentViewController = MemberListUserInfoPopover.makeViewController(for: member)
		memberInformationPopover = popover
		/* The text view is flipped, so `.maxY` is the edge below the name. */
		popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
	}

	func closeMemberInformation() {
		memberInformationPopover?.close()
		memberInformationPopover = nil
	}

	/** Offers the reactions for a message, anchored to the characters the
	 message drew.

	 The window raises the command, because it is a menu command with a
	 conversation to send the reaction to; where the picker opens is the
	 transcript's answer, because only it knows where the message is. A message
	 whose rows are no longer laid out has no anchor, so the pointer is the
	 fallback -- the reader is looking at it either way. */
	func presentReactionPicker(forMessage identifier: String, onPick: @escaping (String) -> Void) {
		closeReactionPicker()
		let picker = ReactionPopover()
		picker.onPick = onPick
		picker.onClose = { [weak self] in self?.reactionPicker = nil }
		reactionPicker = picker
		picker.present(relativeTo: anchorRect(forMessage: identifier), of: textView)
	}

	func closeReactionPicker() {
		reactionPicker?.close()
		reactionPicker = nil
	}

	/// Where a message is drawn, in the text view's coordinates, falling back to
	/// the pointer for a message the layout has not reached.
	func anchorRect(forMessage identifier: String) -> NSRect {
		guard let window, let range = document.range(ofMessage: identifier), range.length > 0 else {
			return pointerRect()
		}
		/* The last character of the message: the picker opens under the end of
		 what it answers rather than under the first of several lines. */
		let tail = NSRange(location: NSMaxRange(range) - 1, length: 1)
		let screenRect = textView.firstRect(forCharacterRange: tail, actualRange: nil)
		guard screenRect.isEmpty == false else { return pointerRect() }
		return textView.convert(window.convertFromScreen(screenRect), from: nil)
	}

	func pointerRect() -> NSRect {
		guard let window else { return .zero }
		let point = textView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
		return NSRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)
	}

	/*  Runs one batch of transcript edits.

	 Every mutation goes through here, which is also why the profile popover is
	 dismissed here: appending, trimming, restyling, a reaction, a decoded image
	 or the unread marker can all move or remove the text the popover is
	 anchored to, and an anchor that moves leaves the popover pointing at
	 someone else's message. */
}
