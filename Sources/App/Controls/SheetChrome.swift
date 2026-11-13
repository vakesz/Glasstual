// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The numbers a sheet is laid out by.

 The margin is the 20 pt inset a macOS sheet keeps between its content and its
 edges, at the sides, the top and below the buttons. It is named here, beside
 the views that use it, rather than per sheet. */
enum SheetMetrics {
	/// 20 pt. What a sheet's content keeps clear of the window's edge.
	static let margin = UISpacing.spacious
	/// 4 pt. Between a sheet's title and the line explaining it.
	static let headingSpacing = UISpacing.tight
}

/** The widths a sheet is offered, so sheets of the same kind open at the same
 size.

 A sheet still takes its height from its content, and stays resizable between
 the minimum and an unbounded maximum: `.presentationSizing(.fitted)` opens it
 at the ideal size. */
enum SheetWidth {
	/// A few fields or one choice: a sign-in, a colour, an invitation.
	case compact
	/// A form of several sections.
	case regular
	/// A table or a list with a detail beside it.
	case wide

	var minimum: CGFloat {
		switch self {
		case .compact: 400
		case .regular: 480
		case .wide: 640
		}
	}

	var ideal: CGFloat {
		switch self {
		case .compact: 440
		case .regular: 540
		case .wide: 720
		}
	}
}

extension View {
	/// Sizes a sheet to one of the app's standard widths. `minHeight` is for a
	/// sheet whose content scrolls and so has no height of its own to offer.
	func sheetFrame(_ width: SheetWidth, minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil) -> some View {
		frame(
			minWidth: width.minimum,
			idealWidth: width.ideal,
			maxWidth: .infinity,
			minHeight: minHeight,
			idealHeight: idealHeight,
			maxHeight: minHeight == nil ? nil : .infinity
		)
	}
}

/** The block a sheet opens with: what it is, and one line saying what it is for.

 Every sheet introduces itself the same way, in the bold headline style macOS
 sheets title themselves with, so the font, the spacing and the margins are
 written once here instead of once per sheet. */
struct SheetHeading: View {
	private let title: Text
	private let subtitle: Text?

	init(_ title: LocalizedStringResource, subtitle: Text? = nil) {
		self.init(Text(title), subtitle: subtitle)
	}

	init(_ title: Text, subtitle: Text? = nil) {
		self.title = title
		self.subtitle = subtitle
	}

	var body: some View {
		VStack(alignment: .leading, spacing: SheetMetrics.headingSpacing) {
			title
				.font(.headline)
				.accessibilityAddTraits(.isHeader)
			if let subtitle {
				subtitle
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding([.horizontal, .top], SheetMetrics.margin)
		.padding(.bottom, UISpacing.regular)
	}
}

/** The row a sheet closes with: whatever the sheet puts on the leading side,
 then Cancel and the button that accepts the sheet, at the trailing edge.

 Escape answers Cancel and Return answers the accepting button in every sheet,
 which is the part worth having in one place: a sheet that spelled the pair out
 itself could give the wrong button the default shortcut. No separator is drawn
 above the row; the buttons sit on the sheet's own background. */
struct SheetActions<Leading: View>: View {
	private let confirmTitle: Text
	private let confirmIsDisabled: Bool
	private let confirmShortcut: KeyboardShortcut?
	private let confirm: () -> Void
	private let cancelTitle: Text
	private let cancel: (() -> Void)?
	private let leading: Leading
	/// What an Accessibility client finds the accepting button by.
	private let confirmIdentifier: String
	/// What an Accessibility client finds Cancel by.
	private let cancelIdentifier: String

	/**
	 - Parameters:
	   - confirmShortcut: The accepting button's key. Return, unless the sheet
	     asks for a decision Return must not make for the person.
	   - cancelTitle: Cancel, unless the sheet is waiting on something and
	     Cancel would read as discarding a finished result.
	   - cancel: Leave out for a sheet that only shows something and closes
	     with one button.
	 */
	init(
		confirmTitle: Text,
		confirmIsDisabled: Bool = false,
		confirmShortcut: KeyboardShortcut? = .defaultAction,
		confirmIdentifier: String = "",
		cancelTitle: Text = Text(PromptStrings.Action.cancel),
		cancelIdentifier: String = "",
		confirm: @escaping () -> Void,
		cancel: (() -> Void)?,
		@ViewBuilder leading: () -> Leading
	) {
		self.confirmTitle = confirmTitle
		self.confirmIsDisabled = confirmIsDisabled
		self.confirmShortcut = confirmShortcut
		self.confirmIdentifier = confirmIdentifier
		self.cancelTitle = cancelTitle
		self.cancelIdentifier = cancelIdentifier
		self.confirm = confirm
		self.cancel = cancel
		self.leading = leading()
	}

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			leading
			Spacer(minLength: UISpacing.loose)
			if let cancel {
				Button(action: cancel) { cancelTitle }
					.keyboardShortcut(.cancelAction)
					.accessibilityIdentifier(cancelIdentifier)
			}
			Button(action: confirm) { confirmTitle }
				.keyboardShortcut(confirmShortcut)
				.disabled(confirmIsDisabled)
				.accessibilityIdentifier(confirmIdentifier)
		}
		.padding(.top, UISpacing.wide)
		.padding([.horizontal, .bottom], SheetMetrics.margin)
	}
}

extension SheetActions where Leading == EmptyView {
	init(
		confirmTitle: Text,
		confirmIsDisabled: Bool = false,
		confirmShortcut: KeyboardShortcut? = .defaultAction,
		confirmIdentifier: String = "",
		cancelTitle: Text = Text(PromptStrings.Action.cancel),
		cancelIdentifier: String = "",
		confirm: @escaping () -> Void,
		cancel: (() -> Void)?
	) {
		self.init(
			confirmTitle: confirmTitle,
			confirmIsDisabled: confirmIsDisabled,
			confirmShortcut: confirmShortcut,
			confirmIdentifier: confirmIdentifier,
			cancelTitle: cancelTitle,
			cancelIdentifier: cancelIdentifier,
			confirm: confirm,
			cancel: cancel,
			leading: { EmptyView() }
		)
	}
}

extension Text {
	/// The confirmation every sheet's accepting button carries unless it names
	/// the thing it is about to do.
	static var sheetConfirmation: Text {
		Text(PromptStrings.Action.confirmation)
	}
}
