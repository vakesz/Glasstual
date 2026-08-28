/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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
import CocoaExtensions

private let textViewWidthPadding: CGFloat = 1.0
private let textViewHeightPadding: CGFloat = 2.0

@objc
public enum TVCTextViewCaretLocation: UInt {
	case onlyLine
	case firstLine
	case middle
	case lastLine
}

@objc(TVCTextViewWithIRCFormatter)
open class TextViewWithIRCFormatter: NSTextView, NSTextViewDelegate, CustomKeyboardEventResponder {
	private var keyEventHandler: KeyEventHandler!
	private var preferredFontStorage: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
	private var preferredFontColorStorage: NSColor = .textColor

	@objc public var preferredFont: NSFont {
		get { preferredFontStorage }
		set {
			/* Fonts and colours are compared by value: `!==` re-applied on an
			 equal-but-distinct instance and skipped on the same instance. */
			guard newValue != preferredFontStorage else {
				return
			}

			preferredFontStorage = newValue
			modifyTypingAttributes([.font: newValue])
		}
	}

	@objc public var preferredFontColor: NSColor {
		get { preferredFontColorStorage }
		set {
			guard newValue != preferredFontColorStorage else {
				return
			}

			preferredFontColorStorage = newValue
			modifyTypingAttributes([.foregroundColor: newValue])
			insertionPointColor = newValue
		}
	}

	override public init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
		super.init(frame: frameRect, textContainer: container)
		prepareInitialState()
	}

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		prepareInitialState()
	}

	private func prepareInitialState() {
		keyEventHandler = KeyEventHandler()

		delegate = self

		if TextualPreferences.rightToLeftFormatting() {
			baseWritingDirection = .rightToLeft
		} else {
			baseWritingDirection = .leftToRight
		}

		textContainerInset = NSSize(width: textViewWidthPadding, height: textViewHeightPadding)
		insertionPointColor = preferredFontColorStorage
		/* Do not touch typingAttributes here — nib decode is still running.
		 Appearance / first textDidChange installs them once the view is live. */
	}

	// MARK: - Keyboard Shortcuts

	public func register(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping KeyEventHandler.Action
	) {
		keyEventHandler.register(key: key, modifiers: modifiers, perform: action)
	}

	public func register(
		character: Character,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping KeyEventHandler.Action
	) {
		keyEventHandler.register(character: character, modifiers: modifiers, perform: action)
	}

	public func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
		keyEventHandler.processKeyEvent(event)
	}

	@objc(keyDownToSuper:)
	public func keyDownToSuper(_ event: NSEvent) {
		super.keyDown(with: event)
	}

	// MARK: - Value Management

	override open var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
		[.string, .fileURL]
	}

	override open var acceptableDragTypes: [NSPasteboard.PasteboardType] {
		[.string, .fileURL]
	}

	@objc public var stringValue: String {
		get { string }
		set {
			textStorage?.replaceCharacters(in: range, with: newValue)
			didChangeText()
		}
	}

	@objc public var stringValueWithIRCFormatting: String {
		get { attributedString().stringFormattedForIRC }
		set {
			guard let formattedValue = (newValue as NSString).attributedString(
				withIRCFormatting: preferredFont,
				preferredFontColor: preferredFontColor,
				honorFormattingPreference: false
			) else {
				return
			}

			attributedStringValue = formattedValue
		}
	}

	@objc open var attributedStringValue: NSAttributedString {
		get { attributedString() }
		set {
			undoManager?.removeAllActions()
			textStorage?.replaceCharacters(in: range, with: newValue)
			didChangeText()
		}
	}

	open func textDidChange(_: Notification) {
		if stringLength < 1 {
			resetTypeSetterAttributes()
		}
	}

	@objc
	public func updateAllFontSizesToMatchTheDefaultFont() {
		guard let textStorage else {
			return
		}

		let newPointSize = preferredFont.pointSize

		textStorage.beginEditing()

		textStorage.enumerateAttribute(.font, in: range, options: []) { value, range, _ in
			guard let value = value as? NSFont else {
				return
			}

			if abs(value.pointSize) == abs(newPointSize) {
				return
			}

			let font = NSFontManager.shared.convert(value, toSize: newPointSize)
			textStorage.removeAttribute(.font, range: range)
			textStorage.addAttribute(.font, value: font, range: range)
		}

		textStorage.endEditing()
	}

	@objc
	public func resetTypeSetterAttributes() {
		typingAttributes = [
			.font: preferredFontStorage,
			.foregroundColor: preferredFontColorStorage,
		]
	}

	private func modifyTypingAttributes(_ typingAttributes: [NSAttributedString.Key: Any]) {
		var typingAttributesMutable = self.typingAttributes
		typingAttributesMutable.merge(typingAttributes) { _, new in new }
		self.typingAttributes = typingAttributesMutable
	}

	@objc(resetFontInRange:)
	public func resetFont(in range: NSRange) {
		textStorage?.addAttributes([.font: preferredFont], range: range)
	}

	@objc(resetFontColorInRange:)
	public func resetFontColor(in range: NSRange) {
		textStorage?.addAttributes([.foregroundColor: preferredFontColor], range: range)
	}

	// MARK: - Line Counting

	/* Everything below goes through NSTextLayoutManager (TextKit 2). Touching
	 -layoutManager on the view would make AppKit fall back to TextKit 1 for
	 good, so nothing in the input field may reference it. */

	private func textRange(forCharacterRange characterRange: NSRange) -> NSTextRange? {
		guard let contentManager = textLayoutManager?.textContentManager else {
			return textLayoutManager?.documentRange
		}

		let documentStart = contentManager.documentRange.location
		guard let start = contentManager.location(documentStart, offsetBy: characterRange.location),
		      let end = contentManager.location(start, offsetBy: characterRange.length)
		else {
			return contentManager.documentRange
		}

		return NSTextRange(location: start, end: end) ?? contentManager.documentRange
	}

	/** Lays out the whole document, then visits every line in order. The
	 character range handed to the block is relative to the document.
	 Return NO from the block to stop. */
	@objc(enumerateLineFragmentsUsingBlock:)
	public func enumerateLineFragments(
		using block: @escaping (NSTextLineFragment, NSRange) -> Bool
	) {
		guard let layoutManager = textLayoutManager,
		      let contentManager = layoutManager.textContentManager
		else {
			return
		}

		let documentStart = contentManager.documentRange.location
		layoutManager.ensureLayout(for: layoutManager.documentRange)

		layoutManager.enumerateTextLayoutFragments(
			from: documentStart,
			options: .ensuresLayout
		) { layoutFragment in
			let fragmentStart = contentManager.offset(
				from: documentStart,
				to: layoutFragment.rangeInElement.location
			)

			for lineFragment in layoutFragment.textLineFragments {
				var characterRange = lineFragment.characterRange
				characterRange.location += fragmentStart

				if block(lineFragment, characterRange) == false {
					return false
				}
			}

			return true
		}
	}

	private var lineCharacterRanges: [NSValue] {
		var ranges: [NSValue] = []

		enumerateLineFragments { _, characterRange in
			ranges.append(NSValue(range: characterRange))
			return true
		}

		return ranges
	}

	@objc public var selectedRect: NSRect {
		guard let layoutManager = textLayoutManager,
		      let textRange = textRange(forCharacterRange: selectedRange())
		else {
			return .zero
		}

		layoutManager.ensureLayout(for: textRange)

		var boundingRect = NSRect.zero

		layoutManager.enumerateTextSegments(
			in: textRange,
			type: .selection,
			options: .rangeNotRequired
		) { _, segmentFrame, _, _ in
			if boundingRect.isEmpty {
				boundingRect = segmentFrame
			} else {
				boundingRect = boundingRect.union(segmentFrame)
			}
			return true
		}

		let containerOrigin = textContainerOrigin
		return boundingRect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
	}

	@objc public var caretLocation: TVCTextViewCaretLocation {
		let currentStringLength = stringLength

		if currentStringLength == 0 {
			return .onlyLine
		}

		let lines = lineCharacterRanges

		if lines.count < 2 {
			return .onlyLine
		}

		let selectedRange = selectedRange()
		let firstLineRange = lines.first!.rangeValue
		let lastLineRange = lines.last!.rangeValue

		/* A caret sitting at the end of a line that wraps or ends with a
		 newline is drawn at the start of the line below, so the end of the
		 first line is excluded. */
		let inFirstLine = selectedRange.location < NSMaxRange(firstLineRange)
		let inLastLine =
			NSMaxRange(selectedRange) == currentStringLength
				|| selectedRange.location >= lastLineRange.location

		if inFirstLine, inLastLine {
			return .onlyLine
		}

		if inFirstLine {
			return .firstLine
		}

		if inLastLine {
			return .lastLine
		}

		return .middle
	}

	@objc(highestHeightBelowHeight:withPadding:)
	public func highestHeight(below maximumHeight: CGFloat, withPadding valuePadding: CGFloat) -> CGFloat {
		var totalLineHeight = valuePadding

		enumerateLineFragments { lineFragment, _ in
			let lineHeight = lineFragment.typographicBounds.height

			if (totalLineHeight + lineHeight) > maximumHeight {
				return false
			}

			totalLineHeight += lineHeight
			return true
		}

		return totalLineHeight
	}
}
