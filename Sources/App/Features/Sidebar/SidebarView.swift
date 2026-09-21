// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import SwiftUI

struct SidebarView: View {
	@Bindable var model: Sidebar
	let redirectTyping: (String) -> Void

	var body: some View {
		VStack(spacing: 0) {
			ViewThatFits(in: .horizontal) {
				filterPicker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
				filterPicker.pickerStyle(.menu)
			}
			.frame(maxWidth: .infinity)
			.padding(.horizontal, UISpacing.regular)
			.padding(.vertical, UISpacing.tight)

			SidebarOutlineRepresentable(model: model, snapshot: SidebarOutlineSnapshot(model: model), redirectTyping: redirectTyping)
				.overlay {
					if model.hasNoFilterMatches {
						emptyResults
					}
				}
		}
	}

	private var filterPicker: some View {
		Picker(.Sidebar.filterLabel, selection: $model.filter) {
			ForEach(SidebarFilter.allCases) { filter in
				Text(filter.title).tag(filter)
			}
		}
		.labelsHidden()
		.accessibilityIdentifier("sidebar-filter")
	}

	@ViewBuilder
	private var emptyResults: some View {
		if !model.filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			ContentUnavailableView.search(text: model.filterText)
		} else if model.filter == .mentions {
			ContentUnavailableView(.Sidebar.noMentionsTitle, systemImage: "at", description: Text(.Sidebar.noMentionsDescription))
		} else {
			ContentUnavailableView(
				.Sidebar.noUnreadTitle,
				systemImage: "checkmark.message",
				description: Text(.Sidebar.conversationsWithNewMessages)
			)
		}
	}
}

private struct SidebarOutlineRepresentable: NSViewRepresentable {
	let model: Sidebar
	let snapshot: SidebarOutlineSnapshot
	let redirectTyping: (String) -> Void

	func makeNSView(context _: Context) -> NSScrollView {
		let scroll = NSScrollView()
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.borderType = .noBorder
		let outline = SidebarOutlineView(model: model, redirectTyping: redirectTyping)
		outline.autoresizingMask = [.width]
		scroll.documentView = outline
		outline.enqueue(snapshot)
		return scroll
	}

	func updateNSView(_ scroll: NSScrollView, context _: Context) {
		(scroll.documentView as? SidebarOutlineView)?.enqueue(snapshot)
	}

	static func dismantleNSView(_ scroll: NSScrollView, coordinator _: ()) {
		(scroll.documentView as? SidebarOutlineView)?.stopUpdates()
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NSScrollView, context _: Context) -> CGSize? {
		CGSize(width: proposal.width ?? MainWindowConstants.sidebarIdealWidth, height: proposal.height ?? 0)
	}
}

/// One setting controls the whole sidebar, including its footer. Changes from
/// Settings and the system's accessibility preferences share this observation.
@Observable
final class SidebarAppearance {
	private(set) var isOpaque = false
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	init() {
		refresh()
		notifications.observe(UserDefaults.didChangeNotification, object: GlasstualUserDefaults.container) { [weak self] _ in
			self?.refresh()
		}
		notifications.observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
		                      center: NSWorkspace.shared.notificationCenter)
		{ [weak self] _ in
			self?.refresh()
		}
	}

	private func refresh() {
		isOpaque = Self.usesOpaqueBackground(
			translucencyDisabled: SettingsKeys.Appearance.disableSidebarTranslucency.value,
			reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
		)
	}

	static func usesOpaqueBackground(translucencyDisabled: Bool, reducesTransparency: Bool) -> Bool {
		translucencyDisabled || reducesTransparency
	}
}

struct SidebarBackgroundView: NSViewRepresentable {
	let isOpaque: Bool

	func makeNSView(context _: Context) -> SidebarBackgroundSurface {
		SidebarBackgroundSurface()
	}

	func updateNSView(_ view: SidebarBackgroundSurface, context _: Context) {
		view.usesOpaqueBackground = isOpaque
	}
}

final class SidebarBackgroundSurface: NSView {
	private let material = NSVisualEffectView()
	var usesOpaqueBackground = false {
		didSet {
			material.isHidden = usesOpaqueBackground
			needsDisplay = true
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		material.material = .sidebar
		material.blendingMode = .behindWindow
		material.state = .followsWindowActiveState
		material.autoresizingMask = [.width, .height]
		material.frame = bounds
		addSubview(material)
		setAccessibilityElement(false)
		material.setAccessibilityElement(false)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("SidebarBackgroundSurface is programmatic")
	}

	override var isOpaque: Bool {
		usesOpaqueBackground
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		guard usesOpaqueBackground else { return }
		NSColor.windowBackgroundColor.setFill()
		dirtyRect.fill()
	}
}
