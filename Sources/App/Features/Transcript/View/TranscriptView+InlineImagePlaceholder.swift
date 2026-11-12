// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

/** The placeholder a line draws for an image that waits for the reader.

 It is an attachment in the image's place, so it lays out, copies and prints
 the way a loaded image does, and the image that replaces it takes the same
 spot. A click, Return or Space with the caret on it, or a VoiceOver press on
 the button it is exposed as, starts the one fetch; the controller decides
 whether that fetch may run. */
extension TranscriptView {
	// MARK: - Document edits

	/// Draws a placeholder below its line. `false` when the line has been
	/// trimmed or already draws something for that link.
	@discardableResult
	func addInlineImagePlaceholder(_ placeholder: TranscriptInlineImagePlaceholder) -> Bool {
		performEditingBatch {
			guard let index = document.addInlineImagePlaceholder(placeholder) else { return false }
			refresh(at: index)
			return true
		}
	}

	func setInlineImagePlaceholderState(
		_ state: TranscriptInlineImagePlaceholder.State,
		for key: TranscriptInlineImagePlaceholder.Key
	) {
		performEditingBatch {
			guard let index = document.setInlineImagePlaceholderState(state, for: key) else { return }
			refresh(at: index)
		}
	}

	func removeInlineImagePlaceholder(_ key: TranscriptInlineImagePlaceholder.Key) {
		performEditingBatch {
			guard let index = document.removeInlineImagePlaceholder(key) else { return }
			refresh(at: index)
		}
	}

	// MARK: - Activation

	/** Asks for the image `key` stands for. `false` when there is no such
	 placeholder or its fetch is already under way, so a click that the text
	 view and the click handler both see still starts one fetch. */
	@discardableResult
	func activateInlineImagePlaceholder(_ key: TranscriptInlineImagePlaceholder.Key) -> Bool {
		guard let placeholder = document.inlineImagePlaceholder(key), placeholder.state.isActivatable,
		      let viewController
		else { return false }
		viewController.loadInlineImageOnRequest(placeholder)
		return true
	}

	/// Return or Space with the caret on a placeholder activates it, as they
	/// do a fold's disclosure link.
	func activateSelectedInlineImagePlaceholder() -> Bool {
		let selection = textView.selectedRange()
		guard selection.length <= 1, let key = inlineImagePlaceholderKey(atCharacterIndex: selection.location)
		else { return false }
		return activateInlineImagePlaceholder(key)
	}

	/** Where the placeholder under the caret is drawn, in the text view's
	 coordinates, while the transcript has the keyboard; `nil` otherwise. The
	 text view draws the system focus ring around it, so a keyboard reader can
	 see which placeholder Return and Space will load. */
	func focusedInlineImagePlaceholderRect() -> NSRect? {
		guard let window, window.firstResponder === textView else { return nil }
		let selection = textView.selectedRange()
		guard selection.length <= 1, inlineImagePlaceholderKey(atCharacterIndex: selection.location) != nil
		else { return nil }
		let screenRect = textView.firstRect(
			forCharacterRange: NSRange(location: selection.location, length: 1), actualRange: nil
		)
		guard screenRect.isEmpty == false else { return nil }
		return textView.convert(window.convertFromScreen(screenRect), from: nil)
	}

	func inlineImagePlaceholderKey(atCharacterIndex index: Int) -> TranscriptInlineImagePlaceholder.Key? {
		guard let storage = textView.textStorage, index != NSNotFound, index >= 0, index < storage.length
		else { return nil }
		return storage.attribute(.transcriptInlineImagePlaceholder, at: index, effectiveRange: nil)
			as? TranscriptInlineImagePlaceholder.Key
	}

	// MARK: - Drawing

	/// What the placeholder says, and what VoiceOver reads as its label.
	func inlineImagePlaceholderLabel(_ placeholder: TranscriptInlineImagePlaceholder) -> String {
		let host = ControlCharacterDisposition.singleLine(placeholder.host)
		return switch placeholder.state {
		case .ready: String(localized: .Transcript.loadImagePlaceholder(host))
		case .loading: String(localized: .Transcript.loadingImagePlaceholder(host))
		case .failed: String(localized: .Transcript.imagePlaceholderFailed(host))
		}
	}

	func append(
		_ placeholder: TranscriptInlineImagePlaceholder,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		let label = inlineImagePlaceholderLabel(placeholder)
		let image = inlineImagePlaceholderImage(placeholder, label: label)
		image.accessibilityDescription = label
		let attachment = NSTextAttachment()
		attachment.image = image
		let attachmentString = NSMutableAttributedString(string: "\n")
		attachmentString.append(NSAttributedString(attachment: attachment))
		attachmentString.addAttribute(
			.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attachmentString.length)
		)
		var attributes: [NSAttributedString.Key: Any] = [
			.accessibilityCustomText: [label],
			.toolTip: placeholder.sourceURL.absoluteString,
			.transcriptInlineImagePlaceholder: placeholder.key,
		]
		if placeholder.state.isActivatable {
			attributes[.cursor] = NSCursor.pointingHand
		}
		attachmentString.addAttributes(attributes, range: NSRange(location: 1, length: 1))
		result.append(attachmentString)
	}

	/** The placeholder's picture: a tinted box with a symbol and the words, in
	 the theme's secondary text colour.

	 Square-cornered, as the loaded image that replaces it is drawn: the image
	 keeps its own edges so Copy and Save Image hand over exactly the picture
	 that arrived, and the placeholder matches it rather than the other way
	 round.

	 It is drawn into a bitmap here, on the main actor, rather than by a drawing
	 handler TextKit may call from elsewhere. A theme change, a resize or a new
	 state redraws the line, and with it this. */
	private func inlineImagePlaceholderImage(_ placeholder: TranscriptInlineImagePlaceholder, label: String) -> NSImage {
		let metrics = TranscriptMetrics.self
		let maximumWidth = metrics.inlineImageMaximumWidth(forTextViewWidth: textView.bounds.width)
		renderedInlineImageWidth = maximumWidth
		let font = NSFont.systemFont(ofSize: max(11, effectiveFont(themeStore).pointSize - 1))
		let color = themeColor(themeStore.theme.palette.secondaryText)
		let lineHeight = ceil(font.ascender - font.descender + font.leading)
		let padding = metrics.inlineImagePlaceholderPadding
		let size = NSSize(
			width: min(metrics.inlineImagePlaceholderBox.width, maximumWidth),
			height: max(metrics.inlineImagePlaceholderBox.height, lineHeight + 2 * padding)
		)
		let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
		guard let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int((size.width * scale).rounded(.up)),
			pixelsHigh: Int((size.height * scale).rounded(.up)),
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
		) else { return NSImage(size: size) }
		bitmap.size = size

		let symbolName = switch placeholder.state {
		case .ready: "photo"
		case .loading: "ellipsis"
		case .failed: "exclamationmark.triangle"
		}
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
		textView.effectiveAppearance.performAsCurrentDrawingAppearance {
			let bounds = NSRect(origin: .zero, size: size)
			let outline = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
			color.withAlphaComponent(0.08).setFill()
			outline.fill()
			color.withAlphaComponent(0.24).setStroke()
			outline.lineWidth = 1
			outline.stroke()

			var textOrigin = padding
			let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize + 2, weight: .regular)
				.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
			if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
				.withSymbolConfiguration(configuration)
			{
				let symbolSize = symbol.size
				symbol.draw(in: NSRect(
					x: padding, y: ((size.height - symbolSize.height) / 2).rounded(),
					width: symbolSize.width, height: symbolSize.height
				))
				textOrigin += symbolSize.width + metrics.inlineImagePlaceholderSpacing
			}

			let style = NSMutableParagraphStyle()
			style.lineBreakMode = .byTruncatingMiddle
			NSAttributedString(string: label, attributes: [
				.font: font, .foregroundColor: color, .paragraphStyle: style,
			]).draw(
				with: NSRect(
					x: textOrigin, y: ((size.height - lineHeight) / 2).rounded(),
					width: max(0, size.width - textOrigin - padding), height: lineHeight
				),
				options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
			)
		}
		NSGraphicsContext.restoreGraphicsState()

		let image = NSImage(size: size)
		image.addRepresentation(bitmap)
		return image
	}

	// MARK: - Accessibility

	/** One button per placeholder on screen, for the text view to offer as
	 children beside its own text.

	 An element is kept per placeholder while it stays on screen, so VoiceOver
	 does not lose its place each time the children are asked for again. */
	func inlineImagePlaceholderAccessibilityElements() -> [NSAccessibilityElement] {
		guard let storage = textView.textStorage, let window else {
			inlineImagePlaceholderElements.removeAll()
			return []
		}
		let visible = window.convertToScreen(textView.convert(textView.visibleRect, to: nil))
		var shown: [(frame: NSRect, element: TranscriptInlineImagePlaceholderElement)] = []
		for (lineNumber, media) in document.inlineMedia {
			guard let index = document.index(ofLine: lineNumber) else { continue }
			let lineRange = NSRange(location: document.location(ofLineAt: index), length: document.length(ofLineAt: index))
			guard NSMaxRange(lineRange) <= storage.length else { continue }
			for case let .placeholder(placeholder) in media {
				var location: Int?
				storage.enumerateAttribute(.transcriptInlineImagePlaceholder, in: lineRange) { value, range, stop in
					if (value as? TranscriptInlineImagePlaceholder.Key) == placeholder.key {
						location = range.location
						stop.pointee = true
					}
				}
				guard let location else { continue }
				let frame = textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
				guard frame.isEmpty == false, frame.intersects(visible) else { continue }
				let key = placeholder.key
				let element = inlineImagePlaceholderElements[key]
					?? TranscriptInlineImagePlaceholderElement(key: key) { [weak self] in
						self?.activateInlineImagePlaceholder(key)
					}
				element.setAccessibilityParent(textView)
				element.setAccessibilityFrame(frame)
				element.setAccessibilityLabel(inlineImagePlaceholderLabel(placeholder))
				element.setAccessibilityHelp(placeholder.sourceURL.absoluteString)
				element.setAccessibilityEnabled(placeholder.state.isActivatable)
				shown.append((frame, element))
			}
		}
		inlineImagePlaceholderElements = Dictionary(
			shown.map { ($0.element.key, $0.element) }, uniquingKeysWith: { first, _ in first }
		)
		// Screen coordinates grow upwards: the topmost placeholder comes first.
		return shown.sorted { $0.frame.maxY > $1.frame.maxY }.map(\.element)
	}
}

/** A placeholder as VoiceOver sees it: a button named for the host it fetches
 from, which a press activates.

 Accessibility calls the element outside actor isolation, so it holds only its
 key and the main-actor action a press forwards to. */
final nonisolated class TranscriptInlineImagePlaceholderElement: NSAccessibilityElement { // nonisolated: xpc-shim
	let key: TranscriptInlineImagePlaceholder.Key
	private let activate: @MainActor @Sendable () -> Void

	init(key: TranscriptInlineImagePlaceholder.Key, activate: @escaping @MainActor @Sendable () -> Void) {
		self.key = key
		self.activate = activate
		super.init()
		setAccessibilityRole(.button)
	}

	override func accessibilityPerformPress() -> Bool {
		let activate = activate
		Task { @MainActor in activate() }
		return true
	}
}
