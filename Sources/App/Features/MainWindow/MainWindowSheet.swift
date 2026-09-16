/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Observation
import SwiftUI

/** One sheet the main window is showing, and whatever that sheet raised on top
 of itself.

 The chain is what makes a sheet-over-a-sheet work: SwiftUI presents a sheet
 from the view it is attached to, so a second one is presented by the first.
 This used to be an array the window indexed into, with two hand-written
 `Binding<Bool>` shims translating "is position N occupied" into a
 presentation and a host that recursed on `index + 1`. */
@MainActor
@Observable
final class MainWindowSheet: Identifiable {
	let id = UUID()
	let owner: AnyObject
	let content: AnyView
	/// The sheet this one raised, if any. Written by the presentation model,
	/// which is what keeps the chain and the owners in step.
	var child: MainWindowSheet?

	@ObservationIgnored private var didFinish = false
	@ObservationIgnored private let onDismiss: @MainActor () -> Void

	init(owner: AnyObject, content: some View, onDismiss: @escaping @MainActor () -> Void) {
		self.owner = owner
		self.content = AnyView(content)
		self.onDismiss = onDismiss
	}

	/// This sheet and everything above it, outermost first.
	var chain: [MainWindowSheet] {
		[self] + (child?.chain ?? [])
	}

	/// Tells the owners their sheets are gone, the innermost first.
	func finish() {
		child?.finish()
		child = nil
		guard didFinish == false else { return }
		didFinish = true
		onDismiss()
	}
}

/// Draws one sheet of the chain, and attaches the next one to it.
struct MainWindowSheetHost: View {
	let model: MainWindowPresentationModel
	@Bindable var presentation: MainWindowSheet

	var body: some View {
		presentation.content
			/* Every hosted sheet is sized by its own content: `.fitted` asks for
			 the content's ideal size and leaves the user free to drag the sheet
			 anywhere between the content's minimum and maximum. */
			.presentationSizing(.fitted)
			.sheet(item: child) { nested in
				MainWindowSheetHost(model: model, presentation: nested)
			}
	}

	private var child: Binding<MainWindowSheet?> {
		Binding(
			get: { presentation.child },
			set: { nested in
				if nested == nil {
					model.dismiss(presentation.child)
				}
			}
		)
	}
}
