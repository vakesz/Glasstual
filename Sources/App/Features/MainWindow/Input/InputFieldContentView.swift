// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// What SwiftUI hosts where the input bar goes: the capsule's contents, the
/// scroll view inside it and the message field inside that.
final class InputFieldContentView: NSView {
	private let inputBarContainerView = NSView()
	private var textViewHeightConstraint: NSLayoutConstraint!

	/** Told in the same pass that moves this view, so what follows the
	 field's edge -- the transcript's bottom inset -- lands in the layout that
	 moved it rather than a run-loop turn later. */
	var frameDidChange: (() -> Void)?

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		frameDidChange?()
	}

	override func setFrameOrigin(_ newOrigin: NSPoint) {
		super.setFrameOrigin(newOrigin)
		frameDidChange?()
	}

	private var textViewStorage: InputField?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		installContainer()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("InputFieldContentView is programmatic")
	}

	private func installContainer() {
		translatesAutoresizingMaskIntoConstraints = false
		inputBarContainerView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(inputBarContainerView)

		let layout = InputBarLayout.self
		textViewHeightConstraint = heightAnchor.constraint(equalToConstant: layout.hostInitialHeight)
		NSLayoutConstraint.activate([
			inputBarContainerView.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: layout.containerHorizontalInset
			),
			trailingAnchor.constraint(
				equalTo: inputBarContainerView.trailingAnchor,
				constant: layout.containerHorizontalInset
			),
			inputBarContainerView.topAnchor.constraint(equalTo: topAnchor, constant: layout.containerTopInset),
			bottomAnchor.constraint(
				equalTo: inputBarContainerView.bottomAnchor,
				constant: layout.containerBottomInset
			),
			textViewHeightConstraint,
		])
	}

	/// The input field, built the first time it is asked for.
	///
	/// It used to come out of the nib. `usesTextKit2` in a xib is accepted by
	/// ibtool and then ignored, so a decoded `NSTextView` is always TextKit 1 —
	/// only `init(usingTextLayoutManager:)` builds the TextKit 2 network, and
	/// only code can call it.
	var textView: InputField {
		if let textViewStorage {
			return textViewStorage
		}

		/* Stored before it is installed. Installing builds the scroll view and
		 configures the field, and anything on that path that reaches back for
		 `textView` must find it already stored rather than build a second one. */
		let textView = InputField(usingTextLayoutManager: true)
		textView.prepareInitialState()
		textViewStorage = textView

		install(textView)

		return textView
	}

	/// Builds the input field, if it is not built already.
	func configure() {
		_ = textView
	}

	private func install(_ textView: InputField) {
		let scrollView = makeScrollView()
		scrollView.documentView = textView

		textView.minSize = NSSize(width: 0, height: InputBarLayout.minimumTextHeight)
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.textContainer?.widthTracksTextView = true
		textView.allowsUndo = true
		textView.isRichText = false
		textView.drawsBackground = false
		textView.insertionPointColor = .controlTextColor
		/* The field's name and its placeholder are the same noun, but they are
		 two different things to VoiceOver: the label is what the field is, the
		 placeholder is what is drawn in it while it is empty. Announcing the
		 placeholder as the label read the field out as a command. */
		textView.setAccessibilityLabel(String(localized: .MainWindow.sendMessage))
		textView.setAccessibilityIdentifier("message-input")

		inputBarContainerView.addSubview(scrollView)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: inputBarContainerView.leadingAnchor),
			inputBarContainerView.trailingAnchor.constraint(
				equalTo: scrollView.trailingAnchor,
				constant: InputBarLayout.scrollViewTrailingInset
			),
			scrollView.topAnchor.constraint(
				equalTo: inputBarContainerView.topAnchor,
				constant: InputBarLayout.scrollViewVerticalInset
			),
			inputBarContainerView.bottomAnchor.constraint(
				equalTo: scrollView.bottomAnchor,
				constant: InputBarLayout.scrollViewVerticalInset
			),
		])

		textView.contentView = self
		textView.heightConstraint = textViewHeightConstraint
		textView.configure()
	}

	private func makeScrollView() -> NSScrollView {
		let scrollView = NSScrollView(frame: .zero)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.borderType = .noBorder
		scrollView.autohidesScrollers = true
		scrollView.hasHorizontalScroller = false
		scrollView.hasVerticalScroller = false
		scrollView.usesPredominantAxisScrolling = false
		scrollView.drawsBackground = false
		scrollView.contentView.drawsBackground = false
		return scrollView
	}

	override var allowsVibrancy: Bool {
		false
	}

	override var isOpaque: Bool {
		false
	}
}
