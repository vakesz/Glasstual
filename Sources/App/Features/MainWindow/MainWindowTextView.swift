/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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
import Combine
import os
import QuartzCore

public typealias TVCMainWindowTextView = MainWindowTextView

private enum MainWindowTextViewNotification {
	static let typingDidChange = Notification.Name("IRCTypingTrackerDidChangeNotification")
	static let typingChannelKey = "channel"
}

private enum MainWindowTextViewAnimation {
	static let accessoryDuration: TimeInterval = 0.18
}

/* The insets the xib used to hold on the scroll view inside the input bar. */
private let inputBarTrailingInset: CGFloat = 10.0
private let inputBarVerticalInset: CGFloat = 3.0
private let inputBarMinimumHeight: CGFloat = 19.0

private let mainWindowTextViewLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "MainWindowTextView"
)

private let observedPreferenceKeys = [
	Preferences.Input.automaticSpellCheck.name,
	Preferences.Input.automaticGrammarCheck.name,
	Preferences.Input.automaticSpellCorrection.name,
	Preferences.Input.smartCopyPaste.name,
	Preferences.Input.smartQuotes.name,
	Preferences.Input.smartDashes.name,
	Preferences.Input.smartLinks.name,
	Preferences.Input.dataDetectors.name,
	Preferences.Input.textReplacement.name,
]

public final class MainWindowTextView: TextViewWithIRCFormatter, AppearanceObserving {
	/** NSTextView has a private accessor named placeholderAttributedString.
	 AppKit may call it, so this property deliberately has another name. */
	private var inputPlaceholderAttributedString: NSAttributedString?
	/** Keyed on the font it was measured with, so a font change invalidates it
	 without anyone having to remember to. */
	private var defaultLineHeightCache: (font: NSFont, height: CGFloat)?

	/* Handed over by the content view, which builds this view in code. They
	 were outlets until the input field had to be a TextKit 2 view, which only
	 an `init(usingTextLayoutManager:)` produces. */
	fileprivate var textViewHeightConstraint: NSLayoutConstraint?
	fileprivate var windowContentViewMinimumHeight: NSLayoutConstraint?
	public fileprivate(set) weak var contentView: MainWindowTextViewContentView?
	fileprivate weak var inputBarContainerView: NSView?
	fileprivate var inputBarTopConstraint: NSLayoutConstraint?

	private var accessoryView: MainWindowInputAccessoryView?
	private var accessoryHeightConstraint: NSLayoutConstraint?
	private var accessoryHeight: CGFloat = 0
	private var observingTyping = false
	private var typingObservations: [Task<Void, Never>] = []
	private weak var typingChannel: IRCChannel?
	private var userInterfaceObjects: MainWindowTextViewAppearance?
	private var observingUserDefaults = false
	private var userDefaultsObservation: Task<Void, Never>?

	/// Finishes the view once the content view has connected it to the nib's
	/// container and constraints.
	///
	/// This was `awakeFromNib`, which is nonisolated — and the view is no longer
	/// decoded from the nib at all, because a nib-instantiated `NSTextView` is
	/// always TextKit 1.
	fileprivate func configure() {
		backgroundColor = .clear
		enclosingScrollView?.drawsBackground = false
		updateTextDirection()
		installAccessoryView()
	}

	// MARK: - Accessory strip

	private func installAccessoryView() {
		guard let contentView,
		      let inputBarContainerView,
		      let inputBarTopConstraint,
		      accessoryView == nil
		else {
			return
		}

		let accessoryView = MainWindowInputAccessoryView(frame: .zero)
		contentView.addSubview(accessoryView)

		let topInset = inputBarTopConstraint.constant
		inputBarTopConstraint.isActive = false

		let heightConstraint = accessoryView.heightAnchor.constraint(equalToConstant: 0)
		let topConstraint = inputBarContainerView.topAnchor.constraint(equalTo: accessoryView.bottomAnchor)

		NSLayoutConstraint.activate([
			accessoryView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topInset),
			accessoryView.leadingAnchor.constraint(equalTo: inputBarContainerView.leadingAnchor),
			accessoryView.trailingAnchor.constraint(equalTo: inputBarContainerView.trailingAnchor),
			heightConstraint,
			topConstraint,
		])

		accessoryView.clipsToBounds = true
		self.accessoryView = accessoryView
		accessoryHeightConstraint = heightConstraint

		accessoryView.contentDidChangeBlock = { [weak self] in
			self?.accessoryContentDidChange()
		}

		accessoryView.cancelReplyBlock = { [weak self] in
			self?.focus()
		}
	}

	private func accessoryContentDidChange() {
		guard let accessoryView, let accessoryHeightConstraint else {
			return
		}

		let height = accessoryView.preferredHeight
		guard height != accessoryHeight else {
			return
		}

		accessoryHeight = height

		if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window == nil {
			accessoryHeightConstraint.constant = height
			recalculateTextViewSize(force: true)
			return
		}

		NSAnimationContext.runAnimationGroup { context in
			context.duration = MainWindowTextViewAnimation.accessoryDuration
			context.timingFunction = CAMediaTimingFunction(name: .easeOut)
			context.allowsImplicitAnimation = true
			accessoryHeightConstraint.animator().constant = height
			recalculateTextViewSize(force: true, animated: true)
		}
	}

	// MARK: - Replies

	public var replyMessageIdentifier: String? {
		accessoryView?.replyMessageIdentifier
	}

	public func beginReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		precondition(messageIdentifier.isEmpty == false)
		accessoryView?.showReply(toMessageIdentifier: messageIdentifier, nickname: nickname, excerpt: excerpt)
		focus()
	}

	public func cancelReply() {
		accessoryView?.hideReply()
	}

	public func consumeReply(into client: IRCClient?) {
		guard let replyMessageIdentifier else {
			return
		}

		client?.nextMessageReplyIdentifier = replyMessageIdentifier
		cancelReply()
	}

	// MARK: - Typing state

	private func setTypingObserved(_ observed: Bool) {
		guard observingTyping != observed else {
			return
		}

		observingTyping = observed

		guard observed else {
			typingObservations.forEach { $0.cancel() }
			typingObservations.removeAll()
			return
		}

		/* `sink` runs its closure nonisolated; awaiting the publisher's values
		 inside a main-actor task delivers on the same later main-queue turn
		 with the isolation checked instead of assumed. */
		typingObservations = [
			Task { @MainActor [weak self] in
				let publisher = NotificationCenter.default
					.publisher(for: MainWindowTextViewNotification.typingDidChange)

				for await notification in publisher.bufferedValues {
					guard let self else {
						return
					}

					typingStateDidChange(notification)
				}
			},
			Task { @MainActor [weak self] in
				let publisher = NotificationCenter.default
					.publisher(for: .mainWindowSelectionChanged)

				for await notification in publisher.bufferedValues {
					guard let self else {
						return
					}

					selectionDidChange(notification)
				}
			},
		]
	}

	private func typingStateDidChange(_ notification: Notification) {
		guard let channel = notification.userInfo?[MainWindowTextViewNotification.typingChannelKey] as? IRCChannel,
		      channel === AppController.shared.mainWindow.selectedChannel
		else {
			return
		}

		updateTypingRow()
	}

	private func selectionDidChange(_: Notification) {
		let selectedChannel = AppController.shared.mainWindow.selectedChannel

		if let typingChannel, typingChannel !== selectedChannel {
			typingChannel.associatedClient?.localUserClearedText(in: typingChannel)
			self.typingChannel = nil
		}

		cancelReply()
		updateTypingRow()
	}

	private func updateTypingRow() {
		let channel = AppController.shared.mainWindow.selectedChannel
		var nicknames: [String] = []

		if let channel, channel.isUtility == false {
			nicknames = channel.associatedClient?.typingTracker.typingNicknames(in: channel) ?? []
		}

		accessoryView?.setTypingNicknames(nicknames)
	}

	private func noteTextChangedForTyping() {
		guard let channel = AppController.shared.mainWindow.selectedChannel,
		      let client = channel.associatedClient
		else {
			return
		}

		let text = stringValue
		client.noteLocalUserTyping(text, in: channel)
		typingChannel = text.isEmpty || text.hasPrefix("/") ? nil : channel
	}

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		setUserDefaultsObserved(window != nil)
		setTypingObserved(window != nil)
	}

	private func setUserDefaultsObserved(_ observed: Bool) {
		guard observingUserDefaults != observed else {
			return
		}

		observingUserDefaults = observed
		let defaults = TextualUserDefaults.container

		guard observed else {
			userDefaultsObservation?.cancel()
			userDefaultsObservation = nil
			return
		}

		observedPreferenceKeys.forEach(applyObservedPreference)

		/* Same reason as the typing observations: `sink` cannot be isolated, and
		 the body writes nine main-actor properties of this view. */
		userDefaultsObservation = Task { @MainActor [weak self] in
			let publisher = NotificationCenter.default.publisher(
				for: UserDefaults.didChangeNotification,
				object: defaults
			)

			for await _ in publisher.bufferedValues {
				guard let self else {
					return
				}

				observedPreferenceKeys.forEach(applyObservedPreference)
			}
		}
	}

	isolated deinit {
		setUserDefaultsObserved(false)
	}

	// MARK: - Appearance

	private func updateVibrancy(with _: MainWindowTextViewAppearance) {
		contentView?.needsDisplay = true
	}

	public func applicationAppearanceChanged() {
		guard let appearance = mainWindow?.userInterfaceObjects.textView else {
			return
		}

		updateAppearance(appearance)
	}

	private func updateAppearance(_ appearance: MainWindowTextViewAppearance) {
		userInterfaceObjects = appearance
		updateVibrancy(with: appearance)
		textContainerInset = appearance.textViewInset

		if let textColor = appearance.textViewTextColor {
			preferredFontColor = textColor
		}

		updateTextBoxCachedPreferredFontSize()
		resetTypeSetterAttributes()
		updateAllFontColorsToMatchTheDefaultFont()
	}

	// MARK: - Spelling

	public func resetSpellingIgnores() {
		NSSpellChecker.shared.setIgnoredWords(
			defaultSpellingIgnores,
			inSpellDocumentWithTag: spellCheckerDocumentTag
		)
	}

	private var defaultSpellingIgnores: [String] {
		(ResourceManager.array(fromResources: "StaticStore", key: "Spelling Ignores") ?? [])
			.compactMap(\.string)
	}

	// MARK: - Text and responder behavior

	private func updateAllFontColorsToMatchTheDefaultFont() {
		guard let textStorage else {
			return
		}

		textStorage.beginEditing()
		textStorage.enumerateAttributes(in: range, options: []) { attributes, effectiveRange, _ in
			let foregroundColorKey = NSAttributedString.Key(
				IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue
			)

			guard attributes[foregroundColorKey] == nil else {
				return
			}

			resetFontColor(in: effectiveRange)
		}
		textStorage.endEditing()
	}

	override public var attributedStringValue: NSAttributedString {
		get { super.attributedStringValue }
		set {
			super.attributedStringValue = newValue
			updateAllFontColorsToMatchTheDefaultFont()
		}
	}

	public func updateTextDirection() {
		baseWritingDirection = TextualPreferences.rightToLeftFormatting() ? .rightToLeft : .leftToRight
	}

	override public func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)
		recalculateTextViewSize()
		noteTextChangedForTyping()
	}

	override public func paste(_ sender: Any?) {
		super.paste(sender)
		recalculateTextViewSize()
	}

	public func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(NSResponder.insertNewline(_:)) {
			mainWindow?.textEntered()
			return true
		}

		if commandSelector == #selector(NSResponder.cancelOperation(_:)), replyMessageIdentifier != nil {
			cancelReply()
			return true
		}

		return false
	}

	// MARK: - Drawing and sizing

	/// TextKit 2 paints the text through its layout fragments and does not
	/// redraw the view for every edit, so a placeholder painted in `draw(_:)`
	/// lingers under typed text. It is a click-transparent label instead, shown
	/// only while the string is empty.
	private let placeholderLabel: PlaceholderLabel = {
		let label = PlaceholderLabel(labelWithString: "")
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.isHidden = true
		return label
	}()

	private func installPlaceholderLabelIfNeeded() {
		guard placeholderLabel.superview == nil else { return }
		addSubview(placeholderLabel)
	}

	private func updatePlaceholderVisibility() {
		placeholderLabel.isHidden = stringLength != 0 || inputPlaceholderAttributedString == nil
	}

	override public func layout() {
		super.layout()

		guard let textContainer else { return }
		let padding = textContainer.lineFragmentPadding
		let origin = textContainerOrigin
		placeholderLabel.frame = NSRect(
			x: origin.x + padding,
			y: origin.y,
			width: max(0, textContainer.size.width - (padding * 2)),
			height: defaultLineHeight
		)
		updatePlaceholderVisibility()
	}

	override public func didChangeText() {
		super.didChangeText()
		updatePlaceholderVisibility()
	}

	override public var string: String {
		get {
			super.string
		}
		set {
			super.string = newValue
			updatePlaceholderVisibility()
		}
	}

	private func updateTextBoxCachedPreferredFontSize() {
		guard let appearance = userInterfaceObjects,
		      appearance.preferredTextViewFontChanged() || inputPlaceholderAttributedString == nil,
		      let placeholderTextColor = appearance.textViewPlaceholderTextColor
		else {
			return
		}

		let preferredFont = appearance.makeTextViewPreferredFont()
		self.preferredFont = preferredFont

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.baseWritingDirection = baseWritingDirection
		paragraphStyle.alignment = .natural
		paragraphStyle.lineBreakMode = .byTruncatingTail

		inputPlaceholderAttributedString = NSAttributedString(
			string: MainWindowStrings.Conversation.inputPlaceholder,
			attributes: [
				.font: preferredFont,
				.foregroundColor: placeholderTextColor,
				.paragraphStyle: paragraphStyle,
			]
		)
		installPlaceholderLabelIfNeeded()
		placeholderLabel.attributedStringValue = inputPlaceholderAttributedString ?? NSAttributedString()
		needsLayout = true
		updatePlaceholderVisibility()
	}

	public func updateTextBasedOnPreferredFontSize() {
		guard let appearance = userInterfaceObjects else {
			return
		}

		let previousFontSize = appearance.textViewPreferredFontSize
		updateTextBoxCachedPreferredFontSize()

		if appearance.textViewPreferredFontSize != previousFontSize {
			updateAllFontSizesToMatchTheDefaultFont()
		}

		recalculateTextViewSize(force: true)
	}

	/// The height of one line in the input field's current font.
	///
	/// This is read from `draw(_:)` and from every size recalculation, so
	/// building a TextKit 2 stack per call would mean one per keystroke and
	/// one per redraw.
	private var defaultLineHeight: CGFloat {
		let font = preferredFont

		if let cache = defaultLineHeightCache, cache.font == font {
			return cache.height
		}

		let contentStorage = NSTextContentStorage()
		let layoutManager = NSTextLayoutManager()
		contentStorage.addTextLayoutManager(layoutManager)
		layoutManager.textContainer = NSTextContainer(size: NSSize(width: 10000, height: 10000))
		contentStorage.attributedString = NSAttributedString(string: "X", attributes: [.font: font])
		layoutManager.ensureLayout(for: layoutManager.documentRange)

		let height = layoutManager.usageBoundsForTextContainer.height
		defaultLineHeightCache = (font, height)
		return height
	}

	public func recalculateTextViewSize() {
		recalculateTextViewSize(force: false)
	}

	public func recalculateTextViewSizeForced() {
		recalculateTextViewSize(force: true)
	}

	private func recalculateTextViewSize(force: Bool, animated: Bool = false) {
		guard let appearance = userInterfaceObjects,
		      let window,
		      let textViewHeightConstraint,
		      let windowContentViewMinimumHeight
		else {
			return
		}

		let contentBorderPadding = appearance.backgroundViewContentBorderPadding
		let minimumHeight = defaultLineHeight + contentBorderPadding
		var backgroundHeight = minimumHeight

		if stringLength > 0 {
			let maximumHeight = window.frame.height - (
				windowContentViewMinimumHeight.constant + contentBorderPadding
			)
			backgroundHeight = highestHeight(below: maximumHeight, withPadding: contentBorderPadding)
			backgroundHeight = max(backgroundHeight, minimumHeight)
		}

		backgroundHeight += accessoryHeight

		/* An unforced recalculation that arrives at the height already in
		 place does not write the constraint: that would invalidate layout for
		 the whole window on every keystroke. */
		if force || backgroundHeight != textViewHeightConstraint.constant {
			if animated {
				textViewHeightConstraint.animator().constant = backgroundHeight
			} else {
				textViewHeightConstraint.constant = backgroundHeight
			}
		}

		guard let scrollContentView = enclosingScrollView?.contentView else {
			return
		}

		var bounds = scrollContentView.bounds
		if bounds.origin.x > 0 {
			bounds.origin.x = 0
			scrollContentView.scroll(to: bounds.origin)
		}
	}

	// MARK: - NSTextView preferences

	/** Preferences drive these nine properties, never the other way round. Each
	 one used to write itself back from a `didSet`, and `UserDefaults.set` posts
	 its notification unconditionally, so any single preference change produced
	 nine writes, each of which produced another notification. */
	private func applyObservedPreference(_ keyPath: String) {
		switch keyPath {
		case Preferences.Input.automaticSpellCheck.name:
			isContinuousSpellCheckingEnabled = TextualPreferences.textFieldAutomaticSpellCheck()
		case Preferences.Input.automaticGrammarCheck.name:
			isGrammarCheckingEnabled = TextualPreferences.textFieldAutomaticGrammarCheck()
		case Preferences.Input.automaticSpellCorrection.name:
			isAutomaticSpellingCorrectionEnabled = TextualPreferences.textFieldAutomaticSpellCorrection()
		case Preferences.Input.smartCopyPaste.name:
			smartInsertDeleteEnabled = TextualPreferences.textFieldSmartCopyPaste()
		case Preferences.Input.smartQuotes.name:
			isAutomaticQuoteSubstitutionEnabled = TextualPreferences.textFieldSmartQuotes()
		case Preferences.Input.smartDashes.name:
			isAutomaticDashSubstitutionEnabled = TextualPreferences.textFieldSmartDashes()
		case Preferences.Input.smartLinks.name:
			isAutomaticLinkDetectionEnabled = TextualPreferences.textFieldSmartLinks()
		case Preferences.Input.dataDetectors.name:
			isAutomaticDataDetectionEnabled = TextualPreferences.textFieldDataDetectors()
		case Preferences.Input.textReplacement.name:
			isAutomaticTextReplacementEnabled = TextualPreferences.textFieldTextReplacement()
		default:
			break
		}
	}
}

@objc(TVCMainWindowTextViewContentView)
public final class MainWindowTextViewContentView: NSView {
	@IBOutlet private var inputBarContainerView: NSView!
	@IBOutlet private var inputBarTopConstraint: NSLayoutConstraint!
	@IBOutlet private var textViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet private var windowContentViewMinimumHeight: NSLayoutConstraint!

	private var textViewStorage: MainWindowTextView?

	/// The input field, built the first time it is asked for.
	///
	/// It used to come out of the nib. `usesTextKit2` in a xib is accepted by
	/// ibtool and then ignored, so a decoded `NSTextView` is always TextKit 1 —
	/// only `init(usingTextLayoutManager:)` builds the TextKit 2 network, and
	/// only code can call it.
	public var textView: MainWindowTextView {
		if let textViewStorage {
			return textViewStorage
		}

		/* Stored before it is laid out, not after: putting the accessory strip
		 together builds controls, and a control joining the window asks the
		 window delegate for a field editor — which answers with this very
		 property. Storing last made that a recursion. */
		let textView = MainWindowTextView(usingTextLayoutManager: true)
		textView.prepareInitialState()
		textViewStorage = textView

		install(textView)

		return textView
	}

	/// Builds the input field, if it is not built already. The main window calls
	/// this once its nib has finished decoding, so that everything reading
	/// `textView` afterwards finds the same one.
	public func configure() {
		_ = textView
	}

	private func install(_ textView: MainWindowTextView) {
		let scrollView = makeScrollView()
		scrollView.documentView = textView

		textView.minSize = NSSize(width: 0, height: inputBarMinimumHeight)
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.textContainer?.widthTracksTextView = true
		textView.allowsUndo = true
		textView.isRichText = false
		textView.drawsBackground = false
		textView.insertionPointColor = .controlTextColor
		textView.setAccessibilityLabel(MainWindowStrings.Conversation.inputPlaceholder)

		inputBarContainerView.addSubview(scrollView)

		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: inputBarContainerView.leadingAnchor),
			inputBarContainerView.trailingAnchor.constraint(
				equalTo: scrollView.trailingAnchor,
				constant: inputBarTrailingInset
			),
			scrollView.topAnchor.constraint(
				equalTo: inputBarContainerView.topAnchor,
				constant: inputBarVerticalInset
			),
			inputBarContainerView.bottomAnchor.constraint(
				equalTo: scrollView.bottomAnchor,
				constant: inputBarVerticalInset
			),
		])

		textView.contentView = self
		textView.inputBarContainerView = inputBarContainerView
		textView.inputBarTopConstraint = inputBarTopConstraint
		textView.textViewHeightConstraint = textViewHeightConstraint
		textView.windowContentViewMinimumHeight = windowContentViewMinimumHeight
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

	override public var allowsVibrancy: Bool {
		false
	}

	override public var isOpaque: Bool {
		false
	}
}

/// A label that never takes the click, so the caret still lands in the text view.
private final class PlaceholderLabel: NSTextField {
	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}
}
