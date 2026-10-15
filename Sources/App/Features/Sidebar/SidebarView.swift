// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import SwiftUI

struct SidebarView: View {
	let model: Sidebar
	let redirectTyping: (String) -> Void

	var body: some View {
		SidebarOutlineRepresentable(model: model, snapshot: SidebarOutlineSnapshot(model: model), redirectTyping: redirectTyping)
			.overlay {
				if model.hasNoFilterMatches {
					emptyResults
				}
			}
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
		CGSize(width: proposal.width ?? MainWindowConstants.sidebarIdealWidth, height: proposal.height ?? 300)
	}
}

/// One setting makes the whole sidebar, footer included, opaque. Otherwise the
/// split view's own sidebar material shows through, and that material already
/// answers the system's Reduce Transparency preference.
@Observable
final class SidebarAppearance {
	private(set) var isOpaque = false
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	init() {
		refresh()
		notifications.observe(UserDefaults.didChangeNotification, object: GlasstualUserDefaults.container) { [weak self] _ in
			self?.refresh()
		}
	}

	private func refresh() {
		let isOpaque = SettingsKeys.Appearance.disableSidebarTranslucency.value
		// Observation reports a write, not a change, and any defaults write lands here.
		guard isOpaque != self.isOpaque else { return }
		self.isOpaque = isOpaque
	}
}
