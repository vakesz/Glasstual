// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Observation

/** The message field.

 An AppKit text view inside a SwiftUI capsule, and no more than that: it reports
 its own responder and key-window transitions, applies the settings that drive
 `NSTextView`'s own behaviours, and keeps the bar's height in step with the text.
 Who is typing is ``InputTypingNotice``'s and the prompt an empty field draws is
 ``InputFieldPlaceholder``'s. */
final class InputField: FormattedTextView {
	/// How much of the window the input bar may take before it stops growing.
	static let maximumWindowHeightFraction: CGFloat = 0.45

	/** Keyed on the font it was measured with, so a font change invalidates it
	 without anyone having to remember to. */
	private var defaultLineHeightCache: (font: NSFont, height: CGFloat)?

	/* Handed over by the content view, which builds this view in code. They
	 were outlets until the input field had to be a TextKit 2 view, which only
	 an `init(usingTextLayoutManager:)` produces. */
	var heightConstraint: NSLayoutConstraint?
	weak var contentView: InputFieldContentView?
	let accessoryModel = InputAccessoryModel()
	let commandDiscovery = SlashCommandDiscoveryModel()
	/// What the capsule around this field watches to draw its focus ring.
	let focusModel = InputFocusModel()
	/// The typing notices this field's conversation owes and is owed. Built on
	/// first use, which is the field joining a window.
	private(set) lazy var typingNotice = InputTypingNotice(accessoryModel: accessoryModel) {
		AppServices.delegate.mainWindow.selectedConversation
	}

	private let placeholder = InputFieldPlaceholder()
	/// The text-size setting the current ``preferredFont`` was built for,
	/// so a font is rebuilt only when the setting moves.
	private var preferredFontSize: MainWindowTextFontSize = .normal
	private var observingUserDefaults = false
	/// The settings store, while the field is in a window.
	private let settingNotifications = NotificationSubscriptions()
	/// Key-window transitions of the window the field is in, so the focus ring
	/// goes out with the window rather than staying lit behind another app.
	private let keyStateNotifications = NotificationSubscriptions()

	/// Finishes the view once the content view has connected its container and
	/// constraints.
	///
	/// This was `awakeFromNib`, which is nonisolated — and the view is no longer
	/// decoded from the nib at all, because a nib-instantiated `NSTextView` is
	/// always TextKit 1.
	func configure() {
		backgroundColor = .clear
		enclosingScrollView?.drawsBackground = false
		updateTextDirection()
	}

	/** The field is an AppKit view inside a SwiftUI capsule, so first-responder
	 status is the signal the capsule draws its focus ring from -- but only half
	 of it. A window keeps its first responder while it is inactive and sends no
	 `resignFirstResponder` when it stops being key, so the ring stayed lit on
	 every window the user had switched away from. The other half is
	 ``windowKeyStateChanged()``. */
	override func becomeFirstResponder() -> Bool {
		let accepted = super.becomeFirstResponder()
		if accepted {
			focusModel.isFirstResponder = true
			refreshSlashCommands()
		}
		return accepted
	}

	override func resignFirstResponder() -> Bool {
		let resigned = super.resignFirstResponder()
		if resigned {
			focusModel.isFirstResponder = false
			refreshSlashCommands()
		}
		return resigned
	}

	/// The window became or stopped being key, or the field changed windows.
	private func windowKeyStateChanged() {
		focusModel.windowIsKey = window?.isKeyWindow == true
		refreshSlashCommands()
	}

	// MARK: - Replies

	var replyMessageIdentifier: String? {
		accessoryModel.replyMessageIdentifier
	}

	func beginReply(
		toMessageIdentifier messageIdentifier: String,
		nickname: String?,
		excerpt: String?
	) {
		precondition(messageIdentifier.isEmpty == false)
		accessoryModel.showReply(toMessageIdentifier: messageIdentifier, nickname: nickname, excerpt: excerpt)
		focus()
	}

	func cancelReply() {
		accessoryModel.hideReply()
	}

	func consumeReply(into session: ServerSession?) {
		guard let replyMessageIdentifier else {
			return
		}

		session?.nextMessageReplyIdentifier = replyMessageIdentifier
		cancelReply()
	}

	// MARK: - Joining a window

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		setUserDefaultsObserved(window != nil)
		typingNotice.setObserved(window != nil)
		setKeyStateObserved(window != nil)
		windowKeyStateChanged()

		guard window != nil else { return }

		updateAppearance()
		placeholder.update(in: self)
	}

	/** Watches the window the field is in for the key state the ring depends on.

	 The subscriptions are dropped when the field leaves the window: they are
	 filtered on that window, and a field that has moved is watching a window
	 nothing will post about. */
	private func setKeyStateObserved(_ observed: Bool) {
		keyStateNotifications.cancelAll()
		guard observed, let window else { return }
		for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
			keyStateNotifications.observe(name, object: window) { [weak self] _ in
				self?.windowKeyStateChanged()
			}
		}
	}

	private func setUserDefaultsObserved(_ observed: Bool) {
		guard observingUserDefaults != observed else {
			return
		}

		observingUserDefaults = observed
		let defaults = GlasstualUserDefaults.container

		guard observed else {
			settingNotifications.cancelAll()
			return
		}

		applyObservedSettings()

		settingNotifications.observe(UserDefaults.didChangeNotification, object: defaults) { [weak self] _ in
			self?.applyObservedSettings()
		}
	}

	isolated deinit {
		/* The two notification bags cancel themselves as they go; this is the
		 flag that says whether the settings are being watched. */
		setUserDefaultsObserved(false)
	}

	// MARK: - Appearance

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		guard window != nil else { return }
		updateAppearance()
	}

	private func updateAppearance() {
		contentView?.needsDisplay = true
		textContainerInset = InputBarLayout.fieldInset
		preferredFontColor = .labelColor

		updateTextBoxCachedPreferredFontSize()
		resetTypeSetterAttributes()
		updateAllFontColorsToMatchTheDefaultFont()
	}

	// MARK: - Spelling

	func resetSpellingIgnores() {
		NSSpellChecker.shared.setIgnoredWords(
			Self.defaultSpellingIgnores,
			inSpellDocumentWithTag: spellCheckerDocumentTag
		)
	}

	/// Read once. The field resets its ignored words on every selection change,
	/// and the bundled list never changes while the application runs.
	private static let defaultSpellingIgnores: [String] = (BundleResources.array(
		fromResources: StaticStoreResource.name,
		key: StaticStoreResource.spellingIgnoresKey
	) ?? []).compactMap(\.string)

	// MARK: - Text and responder behavior

	private func updateAllFontColorsToMatchTheDefaultFont() {
		guard let textStorage else {
			return
		}

		textStorage.beginEditing()
		textStorage.enumerateAttributes(in: range, options: []) { attributes, effectiveRange, _ in
			let foregroundColorKey = NSAttributedString.Key(
				TextFormatterAttributeName.foregroundColorAttributeName.rawValue
			)

			guard attributes[foregroundColorKey] == nil else {
				return
			}

			resetFontColor(in: effectiveRange)
		}
		textStorage.endEditing()
	}

	override var attributedStringValue: NSAttributedString {
		get { super.attributedStringValue }
		set {
			super.attributedStringValue = newValue
			updateAllFontColorsToMatchTheDefaultFont()
		}
	}

	func updateTextDirection() {
		baseWritingDirection = SettingsKeys.Messages.rightToLeftFormatting.value ? .rightToLeft : .leftToRight
	}

	override func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)
		recalculateTextViewSize()
		/* A value set from code, such as a conversation switch refilling the
		 field, is not the user typing. Treating it as typing sent a notice to a
		 conversation the user had only just opened. */
		if isReplacingEntireValue == false {
			typingNotice.noteTextChanged(stringValue)
		}
		refreshSlashCommands()
	}

	override func paste(_ sender: Any?) {
		super.paste(sender)
		recalculateTextViewSize()
	}

	override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
		super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
		refreshSlashCommands()
	}

	override func unmarkText() {
		super.unmarkText()
		refreshSlashCommands()
	}

	func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(NSResponder.insertNewline(_:)) {
			/* AppKit's standard key bindings send `insertNewline:` for Return
			 and for Shift+Return alike, so swallowing the command whole meant
			 Shift+Return sent the message and Option+Return was the only way to
			 get a second line into one. Declining leaves the text view to do
			 what it already does with the key. */
			if hasMarkedText() || NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
				return false
			}
			if acceptIncompleteSlashCommand() {
				return true
			}
			(window as? MainWindow)?.textEntered()
			return true
		}

		if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
			if dismissSlashCommands() {
				return true
			}
			if replyMessageIdentifier != nil {
				cancelReply()
				return true
			}
		}

		/* Tab and Shift-Tab reach the field only when the window declined them,
		 which it does when the setting says Tab does nothing. The keys then
		 move the keyboard to the next or previous control, as they do in a text
		 field. A tab character in a chat message is never what the user meant. */
		if commandSelector == #selector(NSResponder.insertTab(_:)) {
			window?.selectNextKeyView(nil)
			return true
		}

		if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
			window?.selectPreviousKeyView(nil)
			return true
		}

		return false
	}

	// MARK: - Placeholder

	/// The placeholder as the reader sees it, or `nil` when nothing is drawn.
	var drawnPlaceholderText: String? {
		placeholder.drawnText
	}

	override func layout() {
		super.layout()

		placeholder.layout(in: self)
		placeholder.updateVisibility(in: self)
	}

	override func didChangeText() {
		super.didChangeText()
		placeholder.updateVisibility(in: self)
	}

	override var string: String {
		get {
			super.string
		}
		set {
			super.string = newValue
			placeholder.updateVisibility(in: self)
			refreshSlashCommands()
		}
	}

	// MARK: - Drawing and sizing

	private func updateTextBoxCachedPreferredFontSize() {
		let size = SettingsKeys.Input.textViewFontSize.value
		guard size != preferredFontSize || placeholder.attributedString == nil else {
			return
		}

		preferredFontSize = size
		preferredFont = InputBarLayout.font(for: size)

		placeholder.update(in: self)
	}

	func updateTextBasedOnPreferredFontSize() {
		let previousFontSize = preferredFontSize
		updateTextBoxCachedPreferredFontSize()

		if preferredFontSize != previousFontSize {
			updateAllFontSizesToMatchTheDefaultFont()
		}

		recalculateTextViewSize(force: true)
	}

	/// The height of one line in the input field's current font.
	///
	/// This is read from every size recalculation and from every placeholder
	/// layout, so building a TextKit 2 stack per call would mean one per
	/// keystroke and one per redraw.
	var defaultLineHeight: CGFloat {
		let font = preferredFont

		if let cache = defaultLineHeightCache, cache.font == font {
			return cache.height
		}

		let height = TextLineMetrics.lineHeight(for: font)
		defaultLineHeightCache = (font, height)
		return height
	}

	func recalculateTextViewSize() {
		recalculateTextViewSize(force: false)
	}

	private func recalculateTextViewSize(force: Bool) {
		guard let window, let heightConstraint else {
			return
		}

		let contentBorderPadding = InputBarLayout.fieldBorderPadding
		let minimumHeight = defaultLineHeight + contentBorderPadding
		var backgroundHeight = minimumHeight

		if stringLength > 0 {
			/* The transcript keeps the rest. The bar used to be capped against
			 its own minimum-height constraint, which left it free to cover the
			 transcript. */
			let maximumHeight = max(
				0,
				window.frame.height * Self.maximumWindowHeightFraction - contentBorderPadding
			)
			backgroundHeight = highestHeight(below: maximumHeight, withPadding: contentBorderPadding)
			backgroundHeight = max(backgroundHeight, minimumHeight)
		}

		/* An unforced recalculation that arrives at the height already in
		 place does not write the constraint: that would invalidate layout for
		 the whole window on every keystroke. */
		if force || backgroundHeight != heightConstraint.constant {
			heightConstraint.constant = backgroundHeight
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

	// MARK: - NSTextView settings

	/** Settings drive these nine properties, never the other way round: a
	 property that writes its setting back from a `didSet` turns one
	 setting change into nine writes and nine more notifications.

	 All nine on every change. `UserDefaults.didChangeNotification` does not say
	 which key moved, so the list of observed keys and the switch that dispatched
	 on them spelled out "apply every one of them" twice -- and a key in the list
	 with no case in the switch was watched and never applied. */
	private func applyObservedSettings() {
		isContinuousSpellCheckingEnabled = SettingsKeys.Input.automaticSpellCheck.value
		isGrammarCheckingEnabled = SettingsKeys.Input.automaticGrammarCheck.value
		isAutomaticSpellingCorrectionEnabled = SettingsKeys.Input.automaticSpellCorrection.value
		smartInsertDeleteEnabled = SettingsKeys.Input.smartCopyPaste.value
		isAutomaticQuoteSubstitutionEnabled = SettingsKeys.Input.smartQuotes.value
		isAutomaticDashSubstitutionEnabled = SettingsKeys.Input.smartDashes.value
		isAutomaticLinkDetectionEnabled = SettingsKeys.Input.smartLinks.value
		isAutomaticDataDetectionEnabled = SettingsKeys.Input.dataDetectors.value
		isAutomaticTextReplacementEnabled = SettingsKeys.Input.textReplacement.value
	}
}

/** Whether the message field holds the keyboard.

 The field is an AppKit view, so SwiftUI's `@FocusState` never sees it; the
 field reports its own first-responder transitions here and the capsule drawn
 around it observes them.

 First-responder status alone is not the answer. A window keeps its first
 responder while it is inactive, and `resignFirstResponder` is not sent when
 the window stops being key -- so a ring driven by that transition alone stayed
 lit on every background window in the space. Key-window status is the second
 half of the question, and both have to hold. */
@MainActor
@Observable
final class InputFocusModel {
	/// Whether the field is its window's first responder.
	var isFirstResponder = false
	/// Whether that window is the one the keyboard is going to.
	var windowIsKey = false

	/// What the capsule draws its ring from.
	var isFocused: Bool {
		isFirstResponder && windowIsKey
	}
}
