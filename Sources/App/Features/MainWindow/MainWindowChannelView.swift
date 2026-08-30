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
import Combine

@objc(TVCMainWindowChannelView)
public final class MainWindowChannelView: NSView, AppearanceObserving {
	private weak var backingView: LogView?
	private var layoutObservation: Task<Void, Never>?
	private let notificationSubscriptions = NotificationSubscriptions()

	deinit {
		layoutObservation?.cancel()
	}

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
		let backgroundColor = SharedApplication.sharedThemeController().settings.underlyingWindowColor
			?? .textBackgroundColor

		backgroundColor.setFill()
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

		let webView = newBackingView.webView

		backingView = newBackingView

		webView.translatesAutoresizingMaskIntoConstraints = false
		webView.isHidden = newBackingView.isLayingOutView

		addSubview(webView)

		let minimumHeight = webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
		minimumHeight.priority = .defaultHigh

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: topAnchor),
			webView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
			webView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
			minimumHeight,
		])

		layoutObservation = Task { @MainActor [weak self, weak newBackingView, weak webView] in
			guard let newBackingView else {
				return
			}

			for await isLayingOutView in newBackingView.publisher(
				for: \.isLayingOutView,
				options: [.new]
			).bufferedValues {
				guard let self, backingView === newBackingView, let webView else {
					return
				}

				webView.isHidden = isLayingOutView
			}
		}
	}

	private func detachBackingView() {
		layoutObservation?.cancel()
		layoutObservation = nil

		backingView?.webView.removeFromSuperview()
		backingView = nil
	}
}
