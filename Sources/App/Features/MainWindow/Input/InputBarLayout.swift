// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The fixed distances the input bar is built from. The transcript's inset
 is the field's frame -- which already includes `bottomPadding` and the padding
 below the field -- plus `fieldVerticalPadding` for the capsule's top, plus the
 accessory strip; adding `bottomPadding` to it counts that edge twice. */
enum InputBarLayout {
	/// Above and below the field, inside the capsule.
	static let fieldVerticalPadding: CGFloat = 6
	/// Between the capsule and the column's foot; SwiftUI's side only.
	static let bottomPadding: CGFloat = 6
	static let replyBannerHeight: CGFloat = 30
	static let typingRowHeight: CGFloat = 18
	/// What SwiftUI proposes for the field's host view; the field's own height
	/// constraint moves within it as the text grows.
	static let minimumHostHeight: CGFloat = 35
	static let idealHostHeight: CGFloat = 44

	/* The same capsule measured from the AppKit side: the container the field's
	 scroll view sits in, inset from the host view, and the scroll view's own
	 inset within that container. They used to be five literals in
	 `installContainer()` beside four named constants here, describing one shape
	 from two directions. */

	/// The container's inset from the host view.
	static let containerTopInset: CGFloat = 7
	static let containerBottomInset: CGFloat = 6
	static let containerHorizontalInset: CGFloat = 10
	/// The host view's height before the field has measured any text.
	static let hostInitialHeight: CGFloat = 38
	/// The scroll view's inset inside the container.
	static let scrollViewTrailingInset: CGFloat = 10
	static let scrollViewVerticalInset: CGFloat = 3
	/// The shortest the text view itself may be: one line.
	static let minimumTextHeight: CGFloat = 19

	/// The field's text container inset.
	static let fieldInset = NSSize(width: 1, height: 2)
	/// The vertical room the bar's background adds around one line of text,
	/// which is what sets the bar's minimum height.
	static let fieldBorderPadding: CGFloat = 23

	/// The field's font for a text-size setting. The sizes track the system
	/// text styles so they follow the reader's text size settings rather
	/// than fixed point values.
	static func font(for size: MainWindowTextFontSize) -> NSFont {
		switch size {
		case .large:
			NSFont.preferredFont(forTextStyle: .title3, options: [:])
		case .extraLarge:
			NSFont.preferredFont(forTextStyle: .title2, options: [:])
		case .humongous:
			NSFont.preferredFont(forTextStyle: .title1, options: [:])
		default:
			NSFont.preferredFont(forTextStyle: .body, options: [:])
		}
	}

	static func accessoryHeight(replyVisible: Bool, typingVisible: Bool) -> CGFloat {
		var height: CGFloat = 0
		if replyVisible {
			height += replyBannerHeight
		}
		if typingVisible {
			height += typingRowHeight
		}
		if replyVisible, typingVisible {
			height += UISpacing.tight
		}
		return height
	}

	static func accessoryHeight(for model: InputAccessoryModel) -> CGFloat {
		accessoryHeight(
			replyVisible: model.replyMessageIdentifier != nil,
			typingVisible: model.typingNicknames.isEmpty == false
		)
	}
}
