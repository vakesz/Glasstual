/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

@MainActor
private final class TopicEditorScrollView: NSScrollView {
	weak var topicEditor: NSTextView?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		window?.initialFirstResponder = topicEditor
	}
}

@MainActor
struct IRCFormattingTopicEditor: NSViewRepresentable {
	@Binding var formattedText: String

	let accessibilityLabel: String
	let submit: @MainActor () -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = TopicEditorScrollView()
		let textView = TextViewWithIRCFormatter(frame: .zero)

		scrollView.autohidesScrollers = true
		scrollView.borderType = .bezelBorder
		scrollView.drawsBackground = true
		scrollView.hasHorizontalScroller = false
		scrollView.hasVerticalScroller = true

		textView.allowsUndo = true
		textView.autoresizingMask = [.width]
		textView.importsGraphics = false
		textView.isContinuousSpellCheckingEnabled = true
		textView.isHorizontallyResizable = false
		textView.isVerticallyResizable = true
		textView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.minSize = NSSize(width: 0, height: 0)
		textView.preferredFont = .systemFont(ofSize: NSFont.systemFontSize)
		textView.preferredFontColor = .textColor
		textView.stringValueWithIRCFormatting = formattedText
		textView.textContainer?.containerSize = NSSize(
			width: scrollView.contentSize.width,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.textContainer?.widthTracksTextView = true
		textView.setAccessibilityLabel(accessibilityLabel)
		textView.delegate = context.coordinator
		scrollView.documentView = textView
		scrollView.setAccessibilityLabel(accessibilityLabel)
		scrollView.topicEditor = textView

		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		context.coordinator.parent = self

		guard let textView = scrollView.documentView as? TextViewWithIRCFormatter else {
			return
		}

		textView.setAccessibilityLabel(accessibilityLabel)
		scrollView.setAccessibilityLabel(accessibilityLabel)

		if textView.stringValueWithIRCFormatting != formattedText {
			context.coordinator.isApplyingSwiftUIUpdate = true
			textView.stringValueWithIRCFormatting = formattedText
			context.coordinator.isApplyingSwiftUIUpdate = false
		}
	}

	static func dismantleNSView(_ scrollView: NSScrollView, coordinator _: Coordinator) {
		(scrollView.documentView as? TextViewWithIRCFormatter)?.delegate = nil
	}

	@MainActor
	final class Coordinator: NSObject, NSTextViewDelegate {
		var parent: IRCFormattingTopicEditor
		var isApplyingSwiftUIUpdate = false

		init(parent: IRCFormattingTopicEditor) {
			self.parent = parent
		}

		func textDidChange(_ notification: Notification) {
			guard let textView = notification.object as? TextViewWithIRCFormatter else {
				return
			}

			textView.textDidChange(notification)

			guard isApplyingSwiftUIUpdate == false else {
				return
			}

			let formattedText = textView.stringValueWithIRCFormatting
			parent.formattedText = formattedText
		}

		func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
			switch commandSelector {
			case #selector(NSResponder.insertNewline(_:)):
				parent.submit()
				return true
			case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
				return true
			default:
				return false
			}
		}
	}
}
