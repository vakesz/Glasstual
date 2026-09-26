// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** Undo and redo are responder-chain actions AppKit answers without declaring
 them anywhere a `#selector` can name. Declaring them here keeps the two
 selectors checked against a signature instead of spelled as strings. */
@objc
protocol StandardEditingActions {
	func undo(_ sender: Any?)
	func redo(_ sender: Any?)
}

extension MenuGraph {
	/// Commands AppKit routes down the responder chain. Their items carry no
	/// target, so the first responder both validates and performs them.
	static let responderActions: Set<Selector> = [
		#selector(NSTextView.pasteAsPlainText(_:)),
		#selector(NSText.showGuessPanel(_:)),
		#selector(NSText.checkSpelling(_:)),
		#selector(NSTextView.toggleContinuousSpellChecking(_:)),
		#selector(NSTextView.toggleGrammarChecking(_:)),
		#selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
		#selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
		#selector(NSTextView.toggleSmartInsertDelete(_:)),
		#selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
		#selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
		#selector(NSTextView.toggleAutomaticLinkDetection(_:)),
		#selector(NSTextView.toggleAutomaticDataDetection(_:)),
		#selector(NSTextView.toggleAutomaticTextReplacement(_:)),
		#selector(NSResponder.uppercaseWord(_:)),
		#selector(NSResponder.lowercaseWord(_:)),
		#selector(NSResponder.capitalizeWord(_:)),
		#selector(NSTextView.startSpeaking(_:)),
		#selector(NSTextView.stopSpeaking(_:)),
		#selector(StandardEditingActions.undo(_:)),
		#selector(StandardEditingActions.redo(_:)),
		#selector(NSText.cut(_:)),
		#selector(NSText.copy(_:)),
		#selector(NSText.delete(_:)),
		#selector(NSText.selectAll(_:)),
		#selector(NSWindow.toggleFullScreen(_:)),
		#selector(NSWindow.performMiniaturize(_:)),
		#selector(NSWindow.performZoom(_:)),
		#selector(NSApplication.arrangeInFront(_:)),
	]

	static let editEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuEditUndo), .undo, #selector(StandardEditingActions.undo(_:)), key: "z"),
		.item(
			String(localized: .MainWindow.menuEditRedo),
			.redo,
			#selector(StandardEditingActions.redo(_:)),
			key: "z",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(String(localized: .MainWindow.menuEditCut), .cut, #selector(NSText.cut(_:)), key: "x"),
		.item(String(localized: .MainWindow.menuEditCopy), .copy, #selector(NSText.copy(_:)), key: "c"),
		.item(String(localized: .MainWindow.menuEditPaste), .paste, #selector(MenuActionController.paste(_:)), key: "v"),
		.item(
			String(localized: .MainWindow.menuEditPasteAndMatchStyle),
			nil,
			#selector(NSTextView.pasteAsPlainText(_:)),
			key: "v",
			modifiers: [.command, .option, .shift]
		),
		.item(String(localized: .MainWindow.menuEditDelete), .delete, #selector(NSText.delete(_:))),
		.item(String(localized: .MainWindow.menuEditSelectAll), .selectAll, #selector(NSText.selectAll(_:)), key: "a"),
		.separator(),
		.item(String(localized: .MainWindow.menuEditFind), .find, children: [
			.item(
				String(localized: .MainWindow.menuEditFindText),
				.findText,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "f"
			),
			.item(
				String(localized: .MainWindow.menuEditFindNext),
				.findNext,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "g"
			),
			.item(
				String(localized: .MainWindow.menuEditFindPrevious),
				.findPrevious,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "g",
				modifiers: [.command, .shift]
			),
			.item(
				String(localized: .MainWindow.menuEditUseSelectionForFind),
				.useSelectionForFind,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "e"
			),
		]),
		/* The standard AppKit editing commands, with the selectors AppKit's own
			menu uses: every one of them is answered by whatever text view is first
			responder, so the responder chain — not this application — decides
			which are available and which are ticked. They carry no `MenuCommand`
			because nothing here looks them up or updates them. */
		.item(String(localized: .MainWindow.menuEditSpellingAndGrammar), nil, children: [
			.item(
				String(localized: .MainWindow.menuEditShowSpellingAndGrammar),
				nil,
				#selector(NSText.showGuessPanel(_:)),
				key: ":"
			),
			.item(String(localized: .MainWindow.menuEditCheckDocumentNow), nil, #selector(NSText.checkSpelling(_:)), key: ";"),
			.separator(),
			.item(
				String(localized: .MainWindow.menuEditCheckSpellingWhileTyping),
				nil,
				#selector(NSTextView.toggleContinuousSpellChecking(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditCheckGrammarWithSpelling),
				nil,
				#selector(NSTextView.toggleGrammarChecking(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditCorrectSpellingAutomatically),
				nil,
				#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuEditSubstitutions), nil, children: [
			.item(
				String(localized: .MainWindow.menuEditShowSubstitutions),
				nil,
				#selector(NSTextView.orderFrontSubstitutionsPanel(_:))
			),
			.separator(),
			.item(String(localized: .MainWindow.menuEditSmartCopyPaste), nil, #selector(NSTextView.toggleSmartInsertDelete(_:))),
			.item(
				String(localized: .MainWindow.menuEditSmartQuotes),
				nil,
				#selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditSmartDashes),
				nil,
				#selector(NSTextView.toggleAutomaticDashSubstitution(_:))
			),
			.item(String(localized: .MainWindow.menuEditSmartLinks), nil, #selector(NSTextView.toggleAutomaticLinkDetection(_:))),
			.item(
				String(localized: .MainWindow.menuEditDataDetectors),
				nil,
				#selector(NSTextView.toggleAutomaticDataDetection(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditTextReplacement),
				nil,
				#selector(NSTextView.toggleAutomaticTextReplacement(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuEditTransformations), nil, children: [
			.item(String(localized: .MainWindow.menuEditMakeUpperCase), nil, #selector(NSResponder.uppercaseWord(_:))),
			.item(String(localized: .MainWindow.menuEditMakeLowerCase), nil, #selector(NSResponder.lowercaseWord(_:))),
			.item(String(localized: .MainWindow.menuEditCapitalize), nil, #selector(NSResponder.capitalizeWord(_:))),
		]),
		.item(String(localized: .MainWindow.menuEditSpeech), nil, children: [
			.item(String(localized: .MainWindow.menuEditStartSpeaking), nil, #selector(NSTextView.startSpeaking(_:))),
			.item(String(localized: .MainWindow.menuEditStopSpeaking), nil, #selector(NSTextView.stopSpeaking(_:))),
		]),
		/* No Emoji & Symbols and no Start Dictation: AppKit adds both to this
			menu as soon as the main menu is installed -- that is what
			`NSDisabledCharacterPaletteMenuItem` and `NSDisabledDictationMenuItem`
			turn off, and neither key is in this app's Info.plist -- so declaring
			them here showed each one twice. They are the system's to translate too,
			and Start Dictation had no declared selector to send, only the string
			`startDictation:`. */
	]
}
