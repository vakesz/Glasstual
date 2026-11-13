// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// Reads the title-bar inset that a hidden-title SwiftUI scene still reserves.
/// SwiftUI owns the window and applies the resulting content layout.
struct ChannelSpotlightWindowGeometry: NSViewRepresentable {
	@Binding var topInset: CGFloat

	func makeNSView(context _: Context) -> ChannelSpotlightGeometryView {
		let view = ChannelSpotlightGeometryView()
		view.configure { topInset = $0 }
		return view
	}

	func updateNSView(_ view: ChannelSpotlightGeometryView, context _: Context) {
		view.configure { topInset = $0 }
	}

	static func dismantleNSView(_ view: ChannelSpotlightGeometryView, coordinator _: ()) {
		view.stopReporting()
	}
}

final class ChannelSpotlightGeometryView: NSView {
	private var report: ((CGFloat) -> Void)?
	private var reportedInset: CGFloat?
	private var pendingInset: CGFloat?
	private var publicationTask: Task<Void, Never>?

	isolated deinit { publicationTask?.cancel() }

	func configure(report: @escaping (CGFloat) -> Void) {
		self.report = report
		setAccessibilityElement(false)
		measure()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		measure()
	}

	override func layout() {
		super.layout()
		measure()
	}

	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}

	func stopReporting() {
		publicationTask?.cancel()
		publicationTask = nil
		pendingInset = nil
		reportedInset = nil
		report = nil
	}

	private func measure() {
		guard report != nil else { return }
		let inset = window.map { max(0, $0.frame.height - $0.contentLayoutRect.height) } ?? 0
		guard pendingInset != inset else { return }
		publicationTask?.cancel()
		publicationTask = nil
		pendingInset = nil
		guard reportedInset != inset else { return }
		pendingInset = inset
		// Actor scheduling keeps binding writes outside AppKit/SwiftUI layout.
		publicationTask = Task { @MainActor [weak self] in
			guard !Task.isCancelled, let self else { return }
			publicationTask = nil
			pendingInset = nil
			reportedInset = inset
			report?(inset)
		}
	}
}
