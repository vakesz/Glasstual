// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MainWindowLoadingScreen {
	enum Content: Equatable {
		case hidden
		case noServers
		case progress(String)
	}

	private(set) var content = Content.hidden

	var viewIsVisible: Bool {
		content != .hidden
	}

	/// The empty state: the application has no connection configured yet.
	func showNoServersView() {
		content = .noServers
	}

	func showProgressView(withReason reason: String) {
		content = .progress(reason)
	}

	/** Takes the empty state down.

	 The cross-fade is motion, so Reduce Motion drops it and the state simply
	 goes. */
	func hide() {
		guard viewIsVisible else { return }
		withAnimation(ReduceMotion.animation(.easeOut(duration: 0.25))) {
			content = .hidden
		}
	}
}

/** What the conversation column shows while there is no conversation to show:
 the system's empty state when no server is set up, and a small progress
 indicator with its reason while the configuration loads. The sidebar stays
 beside it; there is no splash (HIG Launching). */
struct MainWindowLoadingContent: View {
	@Bindable var model: MainWindowLoadingScreen

	var body: some View {
		Group {
			switch model.content {
			case .hidden:
				EmptyView()
			case .noServers:
				noServers
			case let .progress(reason):
				progress(reason: reason)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.background)
	}

	/// The system's empty state, so the title, the description and the action
	/// carry the placement, spacing and text styles every other one has.
	private var noServers: some View {
		ContentUnavailableView {
			Label(String(localized: .MainWindow.noServers), systemImage: "server.rack")
		} description: {
			Text(verbatim: String(localized: .MainWindow.getStartedDescription))
		} actions: {
			Button(.MainWindow.menuServerAddServer) {
				AppServices.delegate.menuController?.addServer(nil)
			}
			.keyboardShortcut(.defaultAction)
			.accessibilityIdentifier(AccessibilityIdentifier.emptyStateAddServer)
		}
	}

	private func progress(reason: String) -> some View {
		ProgressView {
			Text(verbatim: reason)
				.foregroundStyle(.secondary)
		}
		.controlSize(.small)
	}
}
