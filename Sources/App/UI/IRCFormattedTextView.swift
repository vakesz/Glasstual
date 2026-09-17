// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

private let textViewWidthPadding: CGFloat = 1.0
private let textViewHeightPadding: CGFloat = 2.0

enum TextViewCaretLocation: UInt {
	case onlyLine
	case firstLine
	case middle
	case lastLine
}

class IRCFormattedTextView: NSTextView, NSTextViewDelegate, CustomKeyboardEventResponder {
	private var keyEventHandler: KeyEventHandler!
	private var hasPreparedInitialState = false
	private var preferredFontStorage: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
	private var preferredFontColorStorage: NSColor = .textColor
	private let editingUndoManager = UndoManager()

	override var undoManager: UndoManager? {
		editingUndoManager
	}

	var preferredFont: NSFont {
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

	var preferredFontColor: NSColor {
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

	override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
		super.init(frame: frameRect, textContainer: container)
		prepareInitialState()
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		prepareInitialState()
	}

	/// Idempotent, and reachable from outside, because the input field is built
	/// with `init(usingTextLayoutManager:)` — an inherited Objective-C
	/// convenience initialiser whose chain through the designated ones is
	/// AppKit's business, not something to depend on.
	func prepareInitialState() {
		guard hasPreparedInitialState == false else {
			return
		}

		hasPreparedInitialState = true

		keyEventHandler = KeyEventHandler()

		delegate = self

		if Preferences.Messages.rightToLeftFormatting.value {
			baseWritingDirection = .rightToLeft
		} else {
			baseWritingDirection = .leftToRight
		}

		textContainerInset = NSSize(width: textViewWidthPadding, height: textViewHeightPadding)
		insertionPointColor = preferredFontColorStorage
		/* Do not touch typingAttributes here — the view has no appearance yet.
		 Appearance / first textDidChange installs them once the view is live. */
	}

	// MARK: - Keyboard Shortcuts

	/* `final`: these are never overridden, and a vtable entry for a parameter
	 type carrying an actor annotation is mangled inconsistently between this
	 file and a subclass's metadata, which broke the link. */
	final func register(
		key: KeyCode,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping KeyEventHandler.Action
	) {
		keyEventHandler.register(key: key, modifiers: modifiers, perform: action)
	}

	final func register(
		character: Character,
		modifiers: NSEvent.ModifierFlags = [],
		perform action: @escaping KeyEventHandler.Action
	) {
		keyEventHandler.register(character: character, modifiers: modifiers, perform: action)
	}

	func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
		keyEventHandler.processKeyEvent(event)
	}

	func keyDownToSuper(_ event: NSEvent) {
		super.keyDown(with: event)
	}

	// MARK: - Value Management

	override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
		[.string, .fileURL]
	}

	override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
		[.string, .fileURL]
	}

	/** Replacing the whole field, not editing it.

	 Both value setters drop the undo stack and go through the editing pair. The
	 stack has to go because the ranges recorded in it describe text that is
	 being thrown away wholesale -- a channel switch replaces the field's
	 contents, and the next Undo replayed the previous channel's ranges against
	 the new text. This setter used to do neither, so which of the two a caller
	 reached for decided whether Undo was safe. */
	var stringValue: String {
		get { string }
		set { replaceEntireValue(with: NSAttributedString(string: newValue)) }
	}

	var stringValueWithIRCFormatting: String {
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

	var attributedStringValue: NSAttributedString {
		get { attributedString() }
		set { replaceEntireValue(with: newValue) }
	}

	/// True while one of the value setters replaces the text. A change made
	/// this way came from code, such as a conversation switch refilling the
	/// field, and not from the user typing.
	private(set) var isReplacingEntireValue = false

	/** The one path both value setters take. It asks, replaces the text, tells
	 the delegate, and then forgets the undo actions the old text recorded.

	 Each editor owns its undo manager so clearing it also removes empty undo
	 groups without touching another editor in the same window. */
	private func replaceEntireValue(with newValue: NSAttributedString) {
		let entireRange = range
		guard shouldChangeText(in: entireRange, replacementString: newValue.string) else { return }
		isReplacingEntireValue = true
		defer { isReplacingEntireValue = false }
		textStorage?.replaceCharacters(in: entireRange, with: newValue)
		didChangeText()
		breakUndoCoalescing()
		editingUndoManager.removeAllActions()
	}

	func textDidChange(_: Notification) {
		if stringLength < 1 {
			resetTypeSetterAttributes()
		}
	}

	func updateAllFontSizesToMatchTheDefaultFont() {
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

	func resetTypeSetterAttributes() {
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

	func resetFont(in range: NSRange) {
		textStorage?.addAttributes([.font: preferredFont], range: range)
	}

	func resetFontColor(in range: NSRange) {
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
	func enumerateLineFragments(
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

	var selectedRect: NSRect {
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

	var caretLocation: TextViewCaretLocation {
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

	func highestHeight(below maximumHeight: CGFloat, withPadding valuePadding: CGFloat) -> CGFloat {
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
