/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class MainWindowTextViewMigrationTests: XCTestCase {
	func testObjectiveCRuntimeNamesRemainStableForNibLoading() {
		XCTAssertEqual(NSStringFromClass(MainWindowTextView.self), "TVCMainWindowTextView")
		XCTAssertEqual(
			NSStringFromClass(MainWindowTextViewContentView.self),
			"TVCMainWindowTextViewContentView"
		)
	}

	func testObjectiveCPrivateContractSelectorsRemainAvailable() {
		let textView = MainWindowTextView(frame: .zero)

		XCTAssertTrue(textView.responds(to: NSSelectorFromString("updateTextDirection")))
		XCTAssertTrue(textView.responds(to: NSSelectorFromString("updateTextBasedOnPreferredFontSize")))
		XCTAssertTrue(textView.responds(to: NSSelectorFromString("recalculateTextViewSize")))
		XCTAssertTrue(textView.responds(to: NSSelectorFromString("recalculateTextViewSizeForced")))
		XCTAssertTrue(textView.responds(to: NSSelectorFromString("resetSpellingIgnores")))
		XCTAssertTrue(textView.responds(to: NSSelectorFromString("cancelReply")))
		XCTAssertTrue(textView.responds(to: NSSelectorFromString("consumeReplyIntoClient:")))
	}

	func testAttributedValueUsesPreferredColorForUnformattedText() {
		let textView = MainWindowTextView(frame: .zero)
		textView.preferredFontColor = .systemRed
		textView.attributedStringValue = NSAttributedString(
			string: "plain",
			attributes: [.foregroundColor: NSColor.systemBlue]
		)

		let color = textView.attributedStringValue.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) as? NSColor

		XCTAssertEqual(color, .systemRed)
	}

	func testAttributedValuePreservesExplicitIRCColor() {
		let textView = MainWindowTextView(frame: .zero)
		textView.preferredFontColor = .systemRed
		let formatterKey = NSAttributedString.Key(
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue
		)

		textView.attributedStringValue = NSAttributedString(
			string: "formatted",
			attributes: [
				.foregroundColor: NSColor.systemBlue,
				formatterKey: 4,
			]
		)

		let color = textView.attributedStringValue.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) as? NSColor

		XCTAssertEqual(color, .systemBlue)
	}

	func testContentViewRemainsTransparentAndNonVibrant() {
		let contentView = MainWindowTextViewContentView(frame: .zero)

		XCTAssertFalse(contentView.isOpaque)
		XCTAssertFalse(contentView.allowsVibrancy)
	}
}
