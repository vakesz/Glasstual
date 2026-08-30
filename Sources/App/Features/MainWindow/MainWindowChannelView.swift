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

private func channelViewBackgroundColor() -> NSColor {
	SharedApplication.sharedThemeController().settings.underlyingWindowColor
		?? .textBackgroundColor
}

private final class MainWindowChannelViewLoadingCover: NSView {
	override func draw(_ dirtyRect: NSRect) {
		channelViewBackgroundColor().setFill()
		dirtyRect.fill()
	}
}

@objc(TVCMainWindowChannelView)
public final class MainWindowChannelView: NSView, AppearanceObserving {
	private weak var backingView: LogView?
	private var loadingCoverView: MainWindowChannelViewLoadingCover?
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
			self?.loadingCoverView?.needsDisplay = true
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

		let webView = newBackingView.webView

		backingView = newBackingView

		webView.translatesAutoresizingMaskIntoConstraints = false
		/* A hidden WKWebView does not receive the animation frame that its page
		 uses to report finished layout. Keep it renderable and cover partial
		 content with a native view until that report arrives. */
		webView.isHidden = false

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

		setLoadingCoverVisible(newBackingView.isLayingOutView)

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

				webView.isHidden = false
				setLoadingCoverVisible(isLayingOutView)
			}
		}
	}

	private func setLoadingCoverVisible(_ visible: Bool) {
		if visible {
			guard loadingCoverView == nil else {
				return
			}

			let coverView = MainWindowChannelViewLoadingCover()
			coverView.translatesAutoresizingMaskIntoConstraints = false
			addSubview(coverView)
			NSLayoutConstraint.activate([
				coverView.topAnchor.constraint(equalTo: topAnchor),
				coverView.leadingAnchor.constraint(equalTo: leadingAnchor),
				coverView.trailingAnchor.constraint(equalTo: trailingAnchor),
				coverView.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
			loadingCoverView = coverView
		} else {
			loadingCoverView?.removeFromSuperview()
			loadingCoverView = nil
		}
	}

	private func detachBackingView() {
		layoutObservation?.cancel()
		layoutObservation = nil
		setLoadingCoverVisible(false)

		backingView?.webView.removeFromSuperview()
		backingView = nil
	}
}
