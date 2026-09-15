/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/** The edge between the conversation and the member list: a divider the user
 can drag, with the width it settles on kept across launches.

 The pointer shape is `.pointerStyle`, not a `push()`/`pop()` pair on hover:
 the pair is unbalanced the moment the view disappears mid-hover -- collapse
 the member list from the menu with the pointer over the handle and the
 resize cursor stayed on the stack for the rest of the session. The handle is
 also reachable without the pointer: it takes focus, the arrow keys move it,
 and a double-click returns it to the ideal width. */
struct MemberListResizeHandle: View {
	@Binding var width: CGFloat
	@State private var widthAtDragStart: CGFloat?
	@FocusState private var isFocused: Bool

	var body: some View {
		Divider()
			.frame(width: MainWindowConstants.memberListHandleWidth)
			.contentShape(Rectangle())
			/* The handle takes focus and the arrow keys resize from there, and
			 nothing on screen said so: a control that answers the keyboard has
			 to show when the keyboard is on it. A hairline in the accent colour
			 over the divider's own line, which is the whole control. */
			.overlay {
				if isFocused {
					Rectangle()
						.fill(Color.accentColor)
						.frame(width: 1)
						.accessibilityHidden(true)
				}
			}
			.pointerStyle(.columnResize)
			.gesture(
				DragGesture(minimumDistance: 1)
					.onChanged { value in
						let start = widthAtDragStart ?? width
						widthAtDragStart = start
						apply(start - value.translation.width, persist: false)
					}
					.onEnded { _ in
						widthAtDragStart = nil
						persistWidth()
					}
			)
			.onTapGesture(count: 2) {
				apply(MainWindowConstants.memberListIdealWidth, persist: true)
			}
			.focusable()
			.focused($isFocused)
			/* The width is written back when the key comes up, not on every
			 repeat: a held arrow key otherwise wrote `UserDefaults` -- and
			 posted its change notification, which the message field listens to
			 -- forty times a second. The drag does the same on its own end. */
			.onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat, .up]) { press in
				guard press.phase != .up else {
					persistWidth()
					return .handled
				}
				let step = MainWindowConstants.memberListKeyboardResizeStep
				apply(width + (press.key == .leftArrow ? step : -step), persist: false)
				return .handled
			}
			.accessibilityLabel(MainWindowStrings.Toolbar.memberListWidth)
			.accessibilityHint(MainWindowStrings.Toolbar.memberListWidthHint)
			/* A splitter adjusts, it does not activate: the button trait
			 offered VoiceOver a "press" that does nothing, and described the
			 arrow keys in prose instead of exposing them. */
			.accessibilityValue(Text(Int(width.rounded()), format: .number))
			.accessibilityAdjustableAction { direction in
				let step = MainWindowConstants.memberListKeyboardResizeStep
				switch direction {
				case .increment:
					apply(width + step, persist: true)
				case .decrement:
					apply(width - step, persist: true)
				@unknown default:
					break
				}
			}
			.help(MainWindowStrings.Toolbar.memberListWidth)
	}

	private func apply(_ candidate: CGFloat, persist: Bool) {
		width = MemberListWidthPolicy.clamped(candidate)
		if persist {
			persistWidth()
		}
	}

	private func persistWidth() {
		Preferences.MainWindow.memberListWidth.value = Double(width)
	}
}

/// The widths the member list is allowed to settle on. A drag, an arrow key
/// and the double-click reset all land here, so none of them can put a width
/// into the preference that the column cannot lay out.
nonisolated enum MemberListWidthPolicy { // nonisolated: value
	static func clamped(_ candidate: CGFloat) -> CGFloat {
		min(
			MainWindowConstants.memberListMaximumWidth,
			max(MainWindowConstants.memberListMinimumWidth, candidate)
		)
	}
}
