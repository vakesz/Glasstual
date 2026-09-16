/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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

	/** Takes the overlay down.

	 A full-window cross-fade is the largest piece of motion in the window, so
	 it is the first thing Reduce Motion asks an interface to drop; the overlay
	 simply goes. */
	func hide() {
		guard viewIsVisible else { return }
		withAnimation(ReduceMotion.animation(.easeOut(duration: 0.25))) {
			content = .hidden
		}
	}
}

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
		.background(.regularMaterial)
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
		}
	}

	private func progress(reason: String) -> some View {
		VStack(spacing: UISpacing.wide) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.scaledToFit()
				.frame(width: applicationIconSize, height: applicationIconSize)
				.accessibilityHidden(true)
			Text(verbatim: String(localized: .MainWindow.welcomeToGlasstual))
				.font(.largeTitle)
			HStack(spacing: UISpacing.regular) {
				Text(verbatim: reason)
				ProgressView()
					.controlSize(.small)
			}
		}
		.padding(UISpacing.loose)
	}

	/// The application icon at the size the Finder's own Get Info panel draws
	/// it, scaled with the reader's text size.
	@ScaledMetric private var applicationIconSize: CGFloat = 128
}
