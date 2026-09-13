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

/** What a point in the transcript names. Every question a click or a context
 menu asks — the link under it, the reaction chip, the nickname, the line it
 belongs to — is a question about one character, and this is where a point is
 turned into one. */
extension LogView {
	func contextTarget(at point: NSPoint) -> LogPolicyTarget {
		let target = LogPolicyTarget()
		guard let storage = textView.textStorage, let index = characterIndex(at: point) else { return target }
		target.anchorURL = (storage.attribute(.link, at: index, effectiveRange: nil) as? URL)?.absoluteString
		target.nickname = storage.attribute(.transcriptNickname, at: index, effectiveRange: nil) as? String
		target.lineNumber = storage.attribute(.transcriptLineNumber, at: index, effectiveRange: nil) as? String
		target.lineMessageIdentifier = storage.attribute(
			.transcriptMessageIdentifier,
			at: index,
			effectiveRange: nil
		) as? String
		target.lineType = storage.attribute(.transcriptLineType, at: index, effectiveRange: nil) as? String
		/* The line's author, not whichever name the click landed on: a reply
		 raised from a message body answers the person who wrote it. */
		target.lineNickname = storage.attribute(.transcriptLineNickname, at: index, effectiveRange: nil) as? String
		target.lineExcerpt = storage.attribute(.transcriptExcerpt, at: index, effectiveRange: nil) as? String
		switch storage.attribute(.transcriptAction, at: index, effectiveRange: nil) as? TranscriptAction {
		case let .channel(name): target.channelName = name
		case let .nickname(name): target.nickname = name
		case nil: break
		}
		/* Only an inline image, not every attachment: a delivery receipt is a
		 symbol drawn the same way, and it is not a picture to copy or save. */
		if let address = storage.attribute(.transcriptInlineImage, at: index, effectiveRange: nil) as? String {
			target.inlineImageURL = address
			target.inlineImage = (storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?
				.image
		}
		return target
	}

	/** Answers a click the text view has already handled.

	 A plain click on a name opens that member's profile at once. Double-clicking
	 a name opens a conversation with them instead, and the second click takes
	 the popover the first one opened down again -- waiting out the double-click
	 interval before opening meant the profile trailed the click by however long
	 the reader's Double-click speed is set to. Everything else about the click
	 — the caret, the selection, a link the reader followed — was settled before
	 this ran. */
	func textViewClicked(_ click: TranscriptClick) {
		/* A click that left a selection behind was a drag over the text, and a
		 drag over a name selects the name rather than asking about its owner. */
		guard click.clickCount == 1, click.dragged == false, click.modifiers.isEmpty,
		      textView.selectedRange().length == 0
		else { return }
		if let reaction = clickedReaction(at: click.point) {
			policy.reactionChipClicked(reaction)
			return
		}
		guard let (nickname, range) = clickedNickname(at: click.point) else { return }
		showMemberInformation(for: nickname, spelledIn: range, clickedAt: click.point)
	}

	/// `range` if the storage still spells `nickname` there, and nothing if the
	/// document moved underneath the click.
	private func nicknameRange(spelling nickname: String, at range: NSRange) -> NSRange? {
		guard let storage = textView.textStorage, range.length > 0, NSMaxRange(range) <= storage.length
		else { return nil }
		var current = NSRange(location: NSNotFound, length: 0)
		guard case let .nickname(spelled) = storage.attribute(
			.transcriptAction, at: range.location, effectiveRange: &current
		) as? TranscriptAction, spelled == nickname, NSEqualRanges(current, range) else { return nil }
		return current
	}

	private func showMemberInformation(for nickname: String, spelledIn range: NSRange, clickedAt point: NSPoint) {
		guard let window else { return }
		let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
		/* A range the layout has not reached answers with an empty rect, and a
		 popover anchored to one points at the view's corner rather than at the
		 name; the click itself is always somewhere real. */
		let rect = screenRect.isEmpty
			? NSRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)
			: textView.convert(window.convertFromScreen(screenRect), from: nil)
		showMemberInformation(for: nickname, relativeTo: rect, of: textView)
	}

	/// The reaction chip under a point, or nil where there is none.
	private func clickedReaction(at point: NSPoint) -> TranscriptReactionTarget? {
		guard let storage = textView.textStorage, let index = characterIndex(at: point) else { return nil }
		return storage.attribute(.transcriptReaction, at: index, effectiveRange: nil) as? TranscriptReactionTarget
	}

	/** The character a point in the text view names, or nil where the point is
	 not on the text at all.

	 Every question asked of a click -- the chip under it, the menu's target,
	 the name to show a profile for -- is a question about a character, and
	 `characterIndexForInsertion(at:)` answers a different one: it is the
	 nearest insertion point, so a click in the blank tail of a line, in the
	 gutter beside it, or below the last line all answer with a real character
	 that nothing was drawn at. Holding the point against the line fragment's
	 typographic bounds first is what makes the answer the character the reader
	 pointed at. */
	private func characterIndex(at point: NSPoint) -> Int? {
		guard let storage = textView.textStorage, storage.length > 0,
		      let layoutManager = textView.textLayoutManager
		else { return nil }
		let layoutPoint = layoutPoint(for: point)
		guard let fragment = layoutManager.textLayoutFragment(for: layoutPoint) else { return nil }
		let pointInFragment = NSPoint(
			x: layoutPoint.x - fragment.layoutFragmentFrame.minX,
			y: layoutPoint.y - fragment.layoutFragmentFrame.minY
		)
		guard fragment.textLineFragments.contains(where: { $0.typographicBounds.contains(pointInFragment) })
		else { return nil }
		return min(textView.characterIndexForInsertion(at: point), storage.length - 1)
	}

	/// Layout coordinates start at the container's origin, which the text view
	/// moves to keep a short transcript at the foot of the viewport.
	private func layoutPoint(for point: NSPoint) -> NSPoint {
		let origin = textView.textContainerOrigin
		return NSPoint(x: point.x - origin.x, y: point.y - origin.y)
	}

	/** The nickname under a point in the text view, and the characters that
	 spell it, or nil where there is none. Links are the text view's own, and
	 a click on one has already opened it. */
	private func clickedNickname(at point: NSPoint) -> (String, NSRange)? {
		guard let storage = textView.textStorage, var index = characterIndex(at: point) else { return nil }
		/* An insertion index rounds to the nearer boundary, so a click in the
		 right half of a name's last glyph answers with the character after the
		 name. Stepping back belongs to that case alone: the gap after a name
		 deliberately carries none of its action, and neither does whatever
		 follows an inline mention. */
		if index > 0, let boundary = insertionBoundaryX(at: index), layoutPoint(for: point).x < boundary {
			var runRange = NSRange(location: NSNotFound, length: 0)
			let previous = storage.attribute(
				.transcriptAction, at: index - 1, effectiveRange: &runRange
			) as? TranscriptAction
			if case .nickname = previous, NSMaxRange(runRange) == index {
				index -= 1
			}
		}
		guard storage.attribute(.link, at: index, effectiveRange: nil) == nil else { return nil }
		var range = NSRange(location: NSNotFound, length: 0)
		guard case let .nickname(nickname) = storage.attribute(
			.transcriptAction, at: index, effectiveRange: &range
		) as? TranscriptAction, nickname.isEmpty == false else { return nil }
		return (nickname, range)
	}

	/// Where an insertion boundary sits horizontally, in layout coordinates, so
	/// a click can be told from the glyph on either side of it.
	private func insertionBoundaryX(at index: Int) -> CGFloat? {
		guard let layoutManager = textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager,
		      let location = contentManager.location(contentManager.documentRange.location, offsetBy: index)
		else { return nil }
		var boundary: CGFloat?
		layoutManager.enumerateTextSegments(
			in: NSTextRange(location: location),
			type: .standard,
			options: [.rangeNotRequired]
		) { _, frame, _, _ in
			boundary = frame.minX
			return false
		}
		return boundary
	}

	@objc func contentDoubleClicked(_ recognizer: NSClickGestureRecognizer) {
		/* The first click opened the profile; the conversation this click opens
		 must not leave it behind. */
		closeMemberInformation()
		prepareContextTarget(at: recognizer.location(in: textView))
		if contextMenuTarget.channelName != nil {
			policy.channelNameDoubleClicked(in: self)
		} else if contextMenuTarget.nickname != nil {
			policy.nicknameDoubleClicked(in: self)
		}
	}
}
