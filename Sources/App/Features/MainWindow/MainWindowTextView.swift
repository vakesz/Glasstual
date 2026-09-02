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

private enum MainWindowTextViewNotification {
	static let typingChannelKey = "channel"
}

// Insets for the scroll view inside the input bar.
private let inputBarTrailingInset: CGFloat = 10.0
private let inputBarVerticalInset: CGFloat = 3.0
private let inputBarMinimumHeight: CGFloat = 19.0

/// How much of the window the input bar may take before it stops growing.
enum MainWindowInputBarHeightPolicy {
	/// The transcript keeps the rest. The bar used to be capped against its own
	/// minimum-height constraint, which left it free to cover the transcript.
	static let maximumWindowHeightFraction: CGFloat = 0.45

	static func maximumHeight(windowHeight: CGFloat, padding: CGFloat) -> CGFloat {
		max(0, (windowHeight * maximumWindowHeightFraction) - padding)
	}
}

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
	public fileprivate(set) weak var contentView: MainWindowTextViewContentView?
	public let accessoryModel = MainWindowInputAccessoryModel()
	private var observingTyping = false
	private var typingObservations: [Task<Void, Never>] = []
	private weak var typingChannel: IRCChannel?
	private var userInterfaceObjects: MainWindowTextViewAppearance?
	private var observingUserDefaults = false
	private var userDefaultsObservation: Task<Void, Never>?

	/// Finishes the view once the content view has connected its container and
	/// constraints.
	///
	/// This was `awakeFromNib`, which is nonisolated — and the view is no longer
	/// decoded from the nib at all, because a nib-instantiated `NSTextView` is
	/// always TextKit 1.
	fileprivate func configure() {
		backgroundColor = .clear
		enclosingScrollView?.drawsBackground = false
		updateTextDirection()
	}

	// MARK: - Replies

	public var replyMessageIdentifier: String? {
		accessoryModel.replyMessageIdentifier
	}

	public func beginReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		precondition(messageIdentifier.isEmpty == false)
		accessoryModel.showReply(toMessageIdentifier: messageIdentifier, nickname: nickname, excerpt: excerpt)
		focus()
	}

	public func cancelReply() {
		accessoryModel.hideReply()
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
					.publisher(for: .IRCTypingTrackerDidChange)

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

		accessoryModel.setTypingNicknames(nicknames)
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

		guard window != nil else { return }

		/* The field is put together before it joins the window, so the appearance
		 walk the window runs while it configures itself passes it by. Asking
		 again on the way in is what gives the field its appearance at all. */
		applicationAppearanceChanged()
		updatePlaceholderText()
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
		setTypingObserved(false)
	}

	// MARK: - Appearance

	private func updateVibrancy(with _: MainWindowTextViewAppearance) {
		contentView?.needsDisplay = true
	}

	public func applicationAppearanceChanged() {
		guard let appearance = (window as? MainWindow)?.userInterfaceObjects.textView else {
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
		baseWritingDirection = Preferences.Messages.rightToLeftFormatting.value ? .rightToLeft : .leftToRight
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
			(window as? MainWindow)?.textEntered()
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

	/// The placeholder as the reader sees it, or `nil` when nothing is drawn.
	var drawnPlaceholderText: String? {
		guard placeholderLabel.superview != nil, placeholderLabel.isHidden == false else { return nil }

		return placeholderLabel.stringValue
	}

	private func installPlaceholderLabelIfNeeded() {
		guard placeholderLabel.superview == nil else { return }
		addSubview(placeholderLabel)
		layoutPlaceholderLabel()
	}

	private func layoutPlaceholderLabel() {
		guard let textContainer else { return }

		let padding = textContainer.lineFragmentPadding
		let origin = textContainerOrigin
		placeholderLabel.frame = NSRect(
			x: origin.x + padding,
			y: origin.y,
			width: max(0, textContainer.size.width - (padding * 2)),
			height: defaultLineHeight
		)
	}

	private func updatePlaceholderVisibility() {
		placeholderLabel.isHidden = stringLength != 0 || inputPlaceholderAttributedString == nil
	}

	/** Builds the placeholder out of what the field knows now.

	 It used to be built only from the appearance pass, which reads the main
	 window's appearance objects and so needs the field to already be in that
	 window. The field is built before it joins one — SwiftUI hands it over from
	 `makeNSView`, after the window has run its appearance walk — so on a normal
	 launch nothing ever built the string, the label was never added as a
	 subview, and an empty field showed a caret and nothing else. The appearance
	 colour is used once there is one, and `placeholderTextColor` stands in
	 until then. */
	private func updatePlaceholderText() {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.baseWritingDirection = baseWritingDirection
		paragraphStyle.alignment = .natural
		paragraphStyle.lineBreakMode = .byTruncatingTail

		let placeholder = NSAttributedString(
			string: MainWindowStrings.Conversation.inputPlaceholder,
			attributes: [
				.font: preferredFont,
				.foregroundColor: userInterfaceObjects?.textViewPlaceholderTextColor ?? .placeholderTextColor,
				.paragraphStyle: paragraphStyle,
			]
		)

		inputPlaceholderAttributedString = placeholder
		installPlaceholderLabelIfNeeded()
		placeholderLabel.attributedStringValue = placeholder
		needsLayout = true
		layoutPlaceholderLabel()
		updatePlaceholderVisibility()
	}

	override public func layout() {
		super.layout()

		layoutPlaceholderLabel()
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

	/// The placeholder's colour is not part of the guard: a missing colour is a
	/// reason to draw it in the system's placeholder grey, not a reason to leave
	/// the field without a placeholder.
	private func updateTextBoxCachedPreferredFontSize() {
		guard let appearance = userInterfaceObjects,
		      appearance.preferredTextViewFontChanged() || inputPlaceholderAttributedString == nil
		else {
			return
		}

		preferredFont = appearance.makeTextViewPreferredFont()

		updatePlaceholderText()
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

	private func recalculateTextViewSize(force: Bool) {
		guard let appearance = userInterfaceObjects,
		      let window,
		      let textViewHeightConstraint
		else {
			return
		}

		let contentBorderPadding = appearance.backgroundViewContentBorderPadding
		let minimumHeight = defaultLineHeight + contentBorderPadding
		var backgroundHeight = minimumHeight

		if stringLength > 0 {
			let maximumHeight = MainWindowInputBarHeightPolicy.maximumHeight(
				windowHeight: window.frame.height,
				padding: contentBorderPadding
			)
			backgroundHeight = highestHeight(below: maximumHeight, withPadding: contentBorderPadding)
			backgroundHeight = max(backgroundHeight, minimumHeight)
		}

		/* An unforced recalculation that arrives at the height already in
		 place does not write the constraint: that would invalidate layout for
		 the whole window on every keystroke. */
		if force || backgroundHeight != textViewHeightConstraint.constant {
			textViewHeightConstraint.constant = backgroundHeight
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
			isContinuousSpellCheckingEnabled = Preferences.Input.automaticSpellCheck.value
		case Preferences.Input.automaticGrammarCheck.name:
			isGrammarCheckingEnabled = Preferences.Input.automaticGrammarCheck.value
		case Preferences.Input.automaticSpellCorrection.name:
			isAutomaticSpellingCorrectionEnabled = Preferences.Input.automaticSpellCorrection.value
		case Preferences.Input.smartCopyPaste.name:
			smartInsertDeleteEnabled = Preferences.Input.smartCopyPaste.value
		case Preferences.Input.smartQuotes.name:
			isAutomaticQuoteSubstitutionEnabled = Preferences.Input.smartQuotes.value
		case Preferences.Input.smartDashes.name:
			isAutomaticDashSubstitutionEnabled = Preferences.Input.smartDashes.value
		case Preferences.Input.smartLinks.name:
			isAutomaticLinkDetectionEnabled = Preferences.Input.smartLinks.value
		case Preferences.Input.dataDetectors.name:
			isAutomaticDataDetectionEnabled = Preferences.Input.dataDetectors.value
		case Preferences.Input.textReplacement.name:
			isAutomaticTextReplacementEnabled = Preferences.Input.textReplacement.value
		default:
			break
		}
	}
}

public final class MainWindowTextViewContentView: NSView {
	private let inputBarContainerView = NSView()
	private var textViewHeightConstraint: NSLayoutConstraint!

	private var textViewStorage: MainWindowTextView?

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		installContainer()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("MainWindowTextViewContentView is programmatic")
	}

	private func installContainer() {
		translatesAutoresizingMaskIntoConstraints = false
		inputBarContainerView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(inputBarContainerView)

		let inputBarTopConstraint = inputBarContainerView.topAnchor.constraint(equalTo: topAnchor, constant: 7)
		textViewHeightConstraint = heightAnchor.constraint(equalToConstant: 38)
		NSLayoutConstraint.activate([
			inputBarContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			inputBarContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
			inputBarTopConstraint,
			inputBarContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
			textViewHeightConstraint,
		])
	}

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

	/// Builds the input field, if it is not built already.
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
		textView.textViewHeightConstraint = textViewHeightConstraint
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
