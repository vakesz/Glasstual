/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

@MainActor
public final class ProgressIndicatorSheet: SheetBase {
	private static let contentSize = NSSize(width: 406, height: 60)

	private let content = ProgressIndicatorContent.current
	private let model = ProgressIndicatorModel()

	override public init(window: NSWindow?) {
		precondition(window != nil)
		super.init(window: window)
		installSheet()
	}

	private func installSheet() {
		let rootView = ProgressIndicatorView(model: model, content: content)
		let hostedSheet = NSWindow(
			contentRect: NSRect(origin: .zero, size: Self.contentSize),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)

		hostedSheet.contentView = NSHostingView(rootView: rootView)
		hostedSheet.contentMinSize = Self.contentSize
		hostedSheet.contentMaxSize = Self.contentSize
		hostedSheet.isReleasedWhenClosed = false
		hostedSheet.isRestorable = false
		hostedSheet.tabbingMode = .disallowed
		hostedSheet.title = content.windowTitle
		sheet = hostedSheet
	}

	public func start() {
		model.start()
		startSheet()
	}

	public func stop() {
		model.stop()
		close()
	}
}
