// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import QuartzCore
import SwiftUI
import Testing

@MainActor
@Suite("Rendered chat controls", .serialized)
struct ChatControlsRenderingTests {
	@Test("Command suggestions and argument help fit narrow and wide input bars", arguments: [280, 500], [false, true])
	func commandDiscovery(width: Int, dark: Bool) throws {
		for text in ["/", "/timer 30 1"] {
			let model = SlashCommandDiscoveryModel()
			model.update(text: text, selection: NSRange(location: text.utf16.count, length: 0), isActive: true)
			try #require(model.isVisible)
			let height = SlashCommandDiscoveryView.height(for: model)
			#expect(height > 60 && height < 320)
			if model.isEditingCommand {
				#expect(height > SlashCommandDiscoveryView.rowHeight * 5)
			}
			let root = SlashCommandDiscoveryView(model: model, insert: { _ in })
				.environment(\.colorScheme, dark ? .dark : .light)
				.frame(width: CGFloat(width))
				.background(Color(nsColor: .windowBackgroundColor))
			let mode = model.isEditingCommand ? "list" : "arguments"
			try render(
				root,
				size: NSSize(width: CGFloat(width), height: height),
				dark: dark,
				filename: "commands-\(mode)-\(width)",
				check: { host in
					// The input bar reserves this height before SwiftUI lays out.
					// A larger fitting size would overlap the transcript or editor.
					#expect(host.fittingSize.height <= height + 1)
					#expect(host.fittingSize.width <= CGFloat(width) + 1)
				}
			)
		}
	}

	@Test("The server identity form renders its color and symbol controls", arguments: [false, true])
	func serverIdentity(dark: Bool) throws {
		let style = ServerIdentityStyle(color: .purple, icon: .code)
		let root = Form {
			ServerIdentityPicker(
				style: .constant(style),
				name: "Programming languages and operating systems community"
			)
		}
		.formStyle(.grouped)
		.environment(\.colorScheme, dark ? .dark : .light)
		.frame(width: 560, height: 340)
		.background(Color(nsColor: .windowBackgroundColor))
		try render(
			root,
			size: NSSize(width: 560, height: 340),
			dark: dark,
			filename: "server-identity-560",
			check: { host in
				#expect(host.fittingSize.width <= 561)
				#expect(host.fittingSize.height <= 341)
			}
		)
	}

	private func render<Content: View>(
		_ root: Content,
		size: NSSize,
		dark: Bool,
		filename: String,
		check: (NSHostingView<Content>) -> Void
	) throws {
		let host = NSHostingView(rootView: root)
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: size),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		window.contentView = host
		window.animationBehavior = .none
		window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		window.order(.below, relativeTo: 0)
		host.layoutSubtreeIfNeeded()
		window.displayIfNeeded()
		CATransaction.flush()
		#expect(host.bounds.width > 0 && host.bounds.height > 0)
		check(host)

		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.effectiveAppearance.performAsCurrentDrawingAppearance {
			host.cacheDisplay(in: host.bounds, to: bitmap)
		}
		#expect(bitmap.pixelsWide >= Int(size.width))
		#expect(bitmap.pixelsHigh >= Int(size.height))
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		#expect(png.count > 1000)
		let directory = try #require(ApplicationPaths.applicationSupportURL)
			.appending(path: "review-fixtures", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let appearance = dark ? "dark" : "light"
		try png.write(to: directory.appending(path: "\(filename)-\(appearance).png"), options: .atomic)
	}
}
