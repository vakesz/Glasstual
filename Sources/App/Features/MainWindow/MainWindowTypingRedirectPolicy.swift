/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import SwiftUI

enum MainWindowTypingRedirectPolicy {
	/** Where AppKit puts the keys that are not characters.

	 Tab, Return and Escape arrive as control characters, but the arrow,
	 function, page and Home/End keys are mapped into the Unicode private-use
	 area instead -- so an arrow press in a sidebar passed the control-character
	 test and was inserted into the message field as an undrawable character
	 rather than moving the selection. */
	private static let functionKeys = Unicode.Scalar(0xF700)! ... Unicode.Scalar(0xF8FF)!

	static func text(
		for characters: String,
		commandIsPressed: Bool,
		controlIsPressed: Bool
	) -> String? {
		guard commandIsPressed == false,
		      controlIsPressed == false,
		      characters.isEmpty == false,
		      characters.unicodeScalars.allSatisfy(isTypable)
		else { return nil }

		return characters
	}

	private static func isTypable(_ scalar: Unicode.Scalar) -> Bool {
		CharacterSet.controlCharacters.contains(scalar) == false && functionKeys.contains(scalar) == false
	}
}

private struct MainWindowTypingRedirectModifier: ViewModifier {
	let action: (String) -> Void

	func body(content: Content) -> some View {
		content.onKeyPress { press in
			guard let text = MainWindowTypingRedirectPolicy.text(
				for: press.characters,
				commandIsPressed: press.modifiers.contains(.command),
				controlIsPressed: press.modifiers.contains(.control)
			) else { return .ignored }

			action(text)
			return .handled
		}
	}
}

extension View {
	func redirectsPrintableInput(to action: @escaping (String) -> Void) -> some View {
		modifier(MainWindowTypingRedirectModifier(action: action))
	}
}
