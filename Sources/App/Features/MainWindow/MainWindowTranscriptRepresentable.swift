/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

struct MainWindowTranscriptRepresentable: NSViewRepresentable {
	let logView: LogView?
	/// The field floating over the transcript's foot, measured for the inset.
	var inputField: MainWindowTextViewContentView?
	/// Height of the accessory strip above the field, from what it is showing.
	var accessoryHeight: CGFloat = 0
	/// Whether the loading overlay covers the transcript.
	var isObscured = false

	func makeNSView(context _: Context) -> MainWindowTranscriptHostView {
		let host = MainWindowTranscriptHostView()
		host.show(logView, inputField: inputField, accessoryHeight: accessoryHeight)
		host.isHidden = isObscured
		return host
	}

	func updateNSView(_ host: MainWindowTranscriptHostView, context _: Context) {
		host.show(logView, inputField: inputField, accessoryHeight: accessoryHeight)
		host.isHidden = isObscured
	}

	/** The column is SwiftUI's to size; the transcript takes what it is offered.

	 Left to the default, SwiftUI measures an AppKit view by its Auto Layout
	 fitting size, and the transcript's is whatever its topic bar happens to
	 measure: a few dozen points with no topic, the width of the whole topic on
	 one line with one. The split view then reads that as the detail column's
	 minimum and ideal width, which is how the transcript ended up drawn as a
	 strip a few characters wide beside the member list, and how a long topic
	 pushed the columns out past the window. With no height on offer the answer
	 is zero: the transcript has no height of its own to ask for, the column's
	 ideal height is then the input bar's, and the window decides the rest. */
	func sizeThatFits(
		_ proposal: ProposedViewSize,
		nsView _: MainWindowTranscriptHostView,
		context _: Context
	) -> CGSize? {
		CGSize(width: proposal.width ?? MainWindowConstants.conversationMinimumWidth, height: proposal.height ?? 0)
	}
}

final class MainWindowTranscriptHostView: NSView {
	private weak var logView: LogView?
	private weak var inputField: MainWindowTextViewContentView?
	private var accessoryHeight: CGFloat = 0

	func show(
		_ nextLogView: LogView?,
		inputField nextInputField: MainWindowTextViewContentView?,
		accessoryHeight nextAccessoryHeight: CGFloat
	) {
		defer {
			accessoryHeight = nextAccessoryHeight
			updateBottomInset()
		}
		if inputField !== nextInputField {
			inputField?.frameDidChange = nil
			inputField = nextInputField
			nextInputField?.frameDidChange = { [weak self] in
				self?.updateBottomInset()
			}
		}
		guard logView !== nextLogView else { return }
		logView?.removeFromSuperview()
		logView = nextLogView

		guard let transcriptView = nextLogView else { return }
		transcriptView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(transcriptView)
		NSLayoutConstraint.activate([
			transcriptView.leadingAnchor.constraint(equalTo: leadingAnchor),
			transcriptView.trailingAnchor.constraint(equalTo: trailingAnchor),
			transcriptView.topAnchor.constraint(equalTo: topAnchor),
			transcriptView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	override func layout() {
		super.layout()
		updateBottomInset()
	}

	/** The space beneath the transcript that the input bar covers: from this
	 view's foot up to the field's top edge, then the capsule's padding above
	 the field and the accessory strip. It runs on every layout pass and on
	 every move of the field, and that is safe because it writes no SwiftUI
	 state: the transcript ignores an unchanged inset, and a changed one
	 dirties the transcript alone, not this view. A field that is not in this
	 window yet -- it is re-hosted when the appearance changes -- keeps the
	 inset it had rather than pulling the transcript under the bar and back. */
	private func updateBottomInset() {
		guard let logView, let inputField, let window, inputField.window === window else { return }
		let fieldFrame = inputField.convert(inputField.bounds, to: self)
		let fieldTop = isFlipped ? bounds.maxY - fieldFrame.minY : fieldFrame.maxY
		logView.setBottomContentInset(
			max(0, fieldTop) + MainWindowInputBarLayout.fieldVerticalPadding + accessoryHeight
		)
	}
}
