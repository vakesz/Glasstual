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
import CocoaExtensions

private func channelViewBackgroundColor() -> NSColor {
	SharedApplication.sharedThemeController().backgroundColor
}

public final class MainWindowChannelView: NSView, AppearanceObserving {
	private weak var backingView: LogView?
	private let notificationSubscriptions = NotificationSubscriptions()

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		notificationSubscriptions.cancelAll()

		guard window != nil else {
			return
		}

		notificationSubscriptions.observe(.themeAppearanceChanged) { [weak self] _ in
			self?.appearance = nil
			self?.needsDisplay = true
		}
	}

	override public func draw(_ dirtyRect: NSRect) {
		channelViewBackgroundColor().setFill()
		dirtyRect.fill()
	}

	public func show(_ newBackingView: LogView?) {
		guard backingView !== newBackingView else {
			return
		}

		detachBackingView()

		guard let newBackingView else {
			return
		}

		let transcriptView = newBackingView.view

		backingView = newBackingView
		transcriptView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(transcriptView)

		let minimumHeight = transcriptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
		minimumHeight.priority = .defaultHigh

		NSLayoutConstraint.activate([
			transcriptView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
			transcriptView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
			transcriptView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
			transcriptView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
			minimumHeight,
		])
	}

	private func detachBackingView() {
		backingView?.view.removeFromSuperview()
		backingView = nil
	}
}
