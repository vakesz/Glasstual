/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
	static let selectionDidChange = Notification.Name("TVCMainWindowSelectionChangedNotification")
	static let typingChannelKey = "channel"
}

private enum MainWindowTextViewAnimation {
	static let accessoryDuration: TimeInterval = 0.18
}

private let mainWindowTextViewLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "MainWindowTextView"
)

private let observedPreferenceKeys = [
	"TextFieldAutomaticSpellCheck",
	"TextFieldAutomaticGrammarCheck",
	"TextFieldAutomaticSpellCorrection",
	"TextFieldSmartCopyPaste",
	"TextFieldSmartQuotes",
	"TextFieldSmartDashes",
	"TextFieldSmartLinks",
	"TextFieldDataDetectors",
	"TextFieldTextReplacement",
]

@objc(TVCMainWindowTextView)
public final class MainWindowTextView: TextViewWithIRCFormatter {
	/** NSTextView has a private accessor named placeholderAttributedString.
	 AppKit may call it, so this property deliberately has another name. */
	private var inputPlaceholderAttributedString: NSAttributedString?
	/** Keyed on the font it was measured with, so a font change invalidates it
	 without anyone having to remember to. */
	private var defaultLineHeightCache: (font: NSFont, height: CGFloat)?

	@IBOutlet private var textViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet private var windowContentViewMinimumHeight: NSLayoutConstraint!
	@IBOutlet public var contentView: MainWindowTextViewContentView!
	@IBOutlet private var inputBarContainerView: NSView!
	@IBOutlet private var inputBarTopConstraint: NSLayoutConstraint!

	private var accessoryView: MainWindowInputAccessoryView?
	private var accessoryHeightConstraint: NSLayoutConstraint?
	private var accessoryHeight: CGFloat = 0
	private var observingTyping = false
	private var typingObservations: Set<AnyCancellable> = []
	private weak var typingChannel: IRCChannel?
	private var userInterfaceObjects: MainWindowTextViewAppearance?
	private var observingUserDefaults = false
	private var userDefaultsObservation: AnyCancellable?

	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()

		MainActor.assumeIsolated {
			/* Reading layoutManager makes NSTextView fall back to TextKit 1. All
			 sizing in this class therefore stays on NSTextLayoutManager. */
			if textLayoutManager == nil {
				mainWindowTextViewLogger.error("Input text view is not using TextKit 2")
			}

			backgroundColor = .clear
			enclosingScrollView?.drawsBackground = false
			updateTextDirection()
			installAccessoryView()
		}
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

	@objc public var replyMessageIdentifier: String? {
		accessoryView?.replyMessageIdentifier
	}

	@objc(beginReplyToMessageIdentifier:nickname:excerpt:)
	public func beginReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		precondition(messageIdentifier.isEmpty == false)
		accessoryView?.showReply(toMessageIdentifier: messageIdentifier, nickname: nickname, excerpt: excerpt)
		focus()
	}

	@objc public func cancelReply() {
		accessoryView?.hideReply()
	}

	@objc(consumeReplyIntoClient:)
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

		if observed {
			NotificationCenter.default.publisher(for: MainWindowTextViewNotification.typingDidChange)
				.receive(on: DispatchQueue.main)
				.sink { [weak self] notification in
					MainActor.assumeIsolated {
						self?.typingStateDidChange(notification)
					}
				}
				.store(in: &typingObservations)

			NotificationCenter.default.publisher(for: MainWindowTextViewNotification.selectionDidChange)
				.receive(on: DispatchQueue.main)
				.sink { [weak self] notification in
					MainActor.assumeIsolated {
						self?.selectionDidChange(notification)
					}
				}
				.store(in: &typingObservations)
		} else {
			typingObservations.forEach { $0.cancel() }
			typingObservations.removeAll()
		}
	}

	@objc private func typingStateDidChange(_ notification: Notification) {
		guard let channel = notification.userInfo?[MainWindowTextViewNotification.typingChannelKey] as? IRCChannel,
		      channel === AppController.shared.mainWindow.selectedChannel
		else {
			return
		}

		updateTypingRow()
	}

	@objc private func selectionDidChange(_: Notification) {
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
		MainActor.assumeIsolated {
			setUserDefaultsObserved(window != nil)
			setTypingObserved(window != nil)
		}
	}

	private func setUserDefaultsObserved(_ observed: Bool) {
		guard observingUserDefaults != observed else {
			return
		}

		observingUserDefaults = observed
		let defaults = TextualUserDefaults.shared()

		guard observed else {
			userDefaultsObservation?.cancel()
			userDefaultsObservation = nil
			return
		}

		observedPreferenceKeys.forEach(applyObservedPreference)
		userDefaultsObservation = NotificationCenter.default.publisher(
			for: UserDefaults.didChangeNotification,
			object: defaults
		)
		.receive(on: DispatchQueue.main)
		.sink { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else {
					return
				}
				observedPreferenceKeys.forEach(self.applyObservedPreference)
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

	@objc
	override public func applicationAppearanceChanged() {
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

	@objc public func resetSpellingIgnores() {
		NSSpellChecker.shared.setIgnoredWords(
			defaultSpellingIgnores,
			inSpellDocumentWithTag: spellCheckerDocumentTag
		)
	}

	private var defaultSpellingIgnores: [String] {
		(ResourceManager.array(fromResources: "StaticStore", key: "Spelling Ignores") ?? [])
			.compactMap { $0 as? String }
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

	@objc public func updateTextDirection() {
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

	override public func draw(_ dirtyRect: NSRect) {
		guard needsToDraw(dirtyRect) else {
			return
		}

		super.draw(dirtyRect)

		guard stringLength == 0,
		      let placeholder = inputPlaceholderAttributedString,
		      let textContainer
		else {
			return
		}

		let padding = textContainer.lineFragmentPadding
		let origin = textContainerOrigin
		let placeholderRect = NSRect(
			x: origin.x + padding,
			y: origin.y,
			width: textContainer.size.width - (padding * 2),
			height: defaultLineHeight
		)

		placeholder.draw(in: placeholderRect)
	}

	private func updateTextBoxCachedPreferredFontSize() {
		guard let appearance = userInterfaceObjects,
		      appearance.preferredTextViewFontChanged() || inputPlaceholderAttributedString == nil,
		      let preferredFont = appearance.textViewPreferredFont,
		      let placeholderTextColor = appearance.textViewPlaceholderTextColor
		else {
			return
		}

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
		needsDisplay = true
	}

	@objc public func updateTextBasedOnPreferredFontSize() {
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

	@objc public func recalculateTextViewSize() {
		recalculateTextViewSize(force: false)
	}

	@objc public func recalculateTextViewSizeForced() {
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

	private func applyObservedPreference(_ keyPath: String) {
		switch keyPath {
		case "TextFieldAutomaticSpellCheck":
			isContinuousSpellCheckingEnabled = TextualPreferences.textFieldAutomaticSpellCheck()
		case "TextFieldAutomaticGrammarCheck":
			isGrammarCheckingEnabled = TextualPreferences.textFieldAutomaticGrammarCheck()
		case "TextFieldAutomaticSpellCorrection":
			isAutomaticSpellingCorrectionEnabled = TextualPreferences.textFieldAutomaticSpellCorrection()
		case "TextFieldSmartCopyPaste":
			smartInsertDeleteEnabled = TextualPreferences.textFieldSmartCopyPaste()
		case "TextFieldSmartQuotes":
			isAutomaticQuoteSubstitutionEnabled = TextualPreferences.textFieldSmartQuotes()
		case "TextFieldSmartDashes":
			isAutomaticDashSubstitutionEnabled = TextualPreferences.textFieldSmartDashes()
		case "TextFieldSmartLinks":
			isAutomaticLinkDetectionEnabled = TextualPreferences.textFieldSmartLinks()
		case "TextFieldDataDetectors":
			isAutomaticDataDetectionEnabled = TextualPreferences.textFieldDataDetectors()
		case "TextFieldTextReplacement":
			isAutomaticTextReplacementEnabled = TextualPreferences.textFieldTextReplacement()
		default:
			break
		}
	}

	override public var isContinuousSpellCheckingEnabled: Bool {
		didSet { TextualPreferences.setTextFieldAutomaticSpellCheck(isContinuousSpellCheckingEnabled) }
	}

	override public var isGrammarCheckingEnabled: Bool {
		didSet { TextualPreferences.setTextFieldAutomaticGrammarCheck(isGrammarCheckingEnabled) }
	}

	override public var isAutomaticSpellingCorrectionEnabled: Bool {
		didSet { TextualPreferences.setTextFieldAutomaticSpellCorrection(isAutomaticSpellingCorrectionEnabled) }
	}

	override public var smartInsertDeleteEnabled: Bool {
		didSet { TextualPreferences.setTextFieldSmartCopyPaste(smartInsertDeleteEnabled) }
	}

	override public var isAutomaticQuoteSubstitutionEnabled: Bool {
		didSet { TextualPreferences.setTextFieldSmartQuotes(isAutomaticQuoteSubstitutionEnabled) }
	}

	override public var isAutomaticDashSubstitutionEnabled: Bool {
		didSet { TextualPreferences.setTextFieldSmartDashes(isAutomaticDashSubstitutionEnabled) }
	}

	override public var isAutomaticLinkDetectionEnabled: Bool {
		didSet { TextualPreferences.setTextFieldSmartLinks(isAutomaticLinkDetectionEnabled) }
	}

	override public var isAutomaticDataDetectionEnabled: Bool {
		didSet { TextualPreferences.setTextFieldDataDetectors(isAutomaticDataDetectionEnabled) }
	}

	override public var isAutomaticTextReplacementEnabled: Bool {
		didSet { TextualPreferences.setTextFieldTextReplacement(isAutomaticTextReplacementEnabled) }
	}
}

@objc(TVCMainWindowTextViewContentView)
public final class MainWindowTextViewContentView: NSView {
	@IBOutlet private var textView: MainWindowTextView!

	override public var allowsVibrancy: Bool {
		false
	}

	override public var isOpaque: Bool {
		false
	}
}
