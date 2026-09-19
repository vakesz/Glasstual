// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The numbers a sheet is laid out by.

 The margin is off the four-point grid `UISpacing` names -- it is the inset a
 sheet's own content keeps from the window, not a gap between controls -- so it
 is named here, beside the two views that use it, rather than stretching the
 scale to fit it. */
enum SheetMetrics {
	/// 20 pt. What a sheet's content keeps clear of the window's edge.
	static let margin: CGFloat = 20
	/// 6 pt. Between a sheet's title and the line explaining it.
	static let headingSpacing: CGFloat = 6
}

/** The block a sheet opens with: what it is, and one line saying what it is for.

 Every sheet in the app introduces itself the same way, so the font, the spacing
 and the three margins are written once here instead of once per sheet. */
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
				.font(.title2.weight(.semibold))
			if let subtitle {
				subtitle
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding([.horizontal, .top], SheetMetrics.margin)
		.padding(.bottom, UISpacing.wide)
	}
}

/** The strip a sheet closes with: whatever the sheet puts on the left, then the
 two answers it is waiting for.

 Cancel is the escape key and the confirmation is the return key in every sheet,
 which is the part worth having in one place: a sheet that spelled the pair out
 itself could give the wrong button the default shortcut. */
struct SheetActions<Leading: View>: View {
	private let confirmTitle: Text
	private let confirmIsDisabled: Bool
	private let confirm: () -> Void
	private let cancel: () -> Void
	private let leading: Leading

	init(
		confirmTitle: Text,
		confirmIsDisabled: Bool = false,
		confirm: @escaping () -> Void,
		cancel: @escaping () -> Void,
		@ViewBuilder leading: () -> Leading
	) {
		self.confirmTitle = confirmTitle
		self.confirmIsDisabled = confirmIsDisabled
		self.confirm = confirm
		self.cancel = cancel
		self.leading = leading()
	}

	var body: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: UISpacing.regular) {
				leading
				Spacer()
				Button(PromptStrings.Action.cancel, action: cancel)
					.keyboardShortcut(.cancelAction)
				Button(action: confirm) { confirmTitle }
					.keyboardShortcut(.defaultAction)
					.disabled(confirmIsDisabled)
			}
			.padding(UISpacing.wide)
		}
	}
}

extension SheetActions where Leading == EmptyView {
	init(
		confirmTitle: Text,
		confirmIsDisabled: Bool = false,
		confirm: @escaping () -> Void,
		cancel: @escaping () -> Void
	) {
		self.init(
			confirmTitle: confirmTitle,
			confirmIsDisabled: confirmIsDisabled,
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
