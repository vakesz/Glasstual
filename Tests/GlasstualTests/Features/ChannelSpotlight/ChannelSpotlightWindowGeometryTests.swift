// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel search window geometry", .serialized, .timeLimit(.minutes(1)))
struct ChannelSpotlightWindowGeometryTests {
	@Test("A titled window reports its native inset once across content resizes, then clears on detachment")
	func titleBarInsetSurvivesResize() async throws {
		let window = makeWindow(style: [.titled, .fullSizeContentView])
		defer { window.close() }
		let container = try #require(window.contentView)
		let probe = ChannelSpotlightGeometryView()
		var insets: [CGFloat] = []
		probe.configure { insets.append($0) }
		container.addSubview(probe)
		probe.layout()
		probe.layout()
		#expect(insets.isEmpty, "Publishing must wait until the layout/update call has returned")
		let nativeInset = window.frame.height - window.contentLayoutRect.height
		try #require(nativeInset > 0)
		try await waitUntil { !insets.isEmpty }
		#expect(insets == [nativeInset])

		for height in [CGFloat(200), 400, 76] {
			window.setContentSize(NSSize(width: 600, height: height))
			container.layoutSubtreeIfNeeded()
			probe.layout()
			#expect(window.frame.height - window.contentLayoutRect.height == nativeInset)
		}
		probe.removeFromSuperview()
		try await waitUntil { insets.last == 0 }
		#expect(insets == [nativeInset, 0])
	}

	@Test("Detaching before deferred delivery cancels the old window inset")
	func detachCancelsPendingInset() async throws {
		let window = makeWindow(style: [.titled, .fullSizeContentView])
		defer { window.close() }
		let container = try #require(window.contentView)
		let probe = ChannelSpotlightGeometryView()
		var insets: [CGFloat] = []
		probe.configure { insets.append($0) }
		container.addSubview(probe)
		probe.removeFromSuperview()
		#expect(insets.isEmpty)
		try await waitUntil { !insets.isEmpty }
		#expect(insets == [0])
	}

	@Test("A window without title-bar chrome reports zero without changing the window")
	func borderlessWindowHasNoInset() async throws {
		let window = makeWindow(style: .borderless)
		defer { window.close() }
		let container = try #require(window.contentView)
		let frame = window.frame
		let style = window.styleMask
		let probe = ChannelSpotlightGeometryView()
		var insets: [CGFloat] = []
		probe.configure { insets.append($0) }
		container.addSubview(probe)
		probe.layout()
		try await waitUntil { !insets.isEmpty }
		#expect(insets == [0])
		#expect(window.frame == frame)
		#expect(window.styleMask == style)
		#expect(probe.hitTest(.zero) == nil)
	}

	private func makeWindow(style: NSWindow.StyleMask) -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(x: -4000, y: -4000, width: 600, height: 76),
			styleMask: style, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func waitUntil(_ condition: () -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while !condition(), clock.now < deadline {
			try await Task.sleep(for: .milliseconds(1))
		}
		try #require(condition())
	}
}
