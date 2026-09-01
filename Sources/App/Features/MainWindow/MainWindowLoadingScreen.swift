/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
public final class MainWindowLoadingScreen {
	enum Content: Equatable {
		case hidden
		case welcome
		case progress(String)
	}

	private(set) var content = Content.hidden

	@ObservationIgnored var visibilityDidChange: ((Bool) -> Void)?

	public var viewIsVisible: Bool {
		content != .hidden
	}

	public func configure() {}

	public func showWelcomeAddServerView() {
		show(.welcome)
	}

	public func showProgressView(withReason reason: String) {
		show(.progress(reason))
	}

	public func setProgressViewReason(_ reason: String) {
		guard case .progress = content else { return }
		content = .progress(reason)
	}

	public func hide() {
		hideAnimated(false)
	}

	public func hideAnimated() {
		hideAnimated(true)
	}

	public func hideAnimated(_ animated: Bool) {
		guard viewIsVisible else { return }
		visibilityDidChange?(false)
		if animated {
			withAnimation(.easeOut(duration: 0.25)) {
				content = .hidden
			}
		} else {
			content = .hidden
		}
	}

	private func show(_ content: Content) {
		self.content = content
		visibilityDidChange?(true)
	}
}

struct MainWindowLoadingContent: View {
	@Bindable var model: MainWindowLoadingScreen

	var body: some View {
		Group {
			switch model.content {
			case .hidden:
				EmptyView()
			case .welcome:
				ViewThatFits(in: .vertical) {
					welcome(iconSize: 150, spacing: 14, padding: 28)
					welcome(iconSize: 72, spacing: 8, padding: 12)
				}
			case let .progress(reason):
				ViewThatFits(in: .vertical) {
					progress(reason: reason, iconSize: 150, spacing: 14, padding: 28)
					progress(reason: reason, iconSize: 72, spacing: 8, padding: 12)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.regularMaterial)
	}

	private func welcome(iconSize: CGFloat, spacing: CGFloat, padding: CGFloat) -> some View {
		VStack(spacing: spacing) {
			applicationIcon(size: iconSize)
			Text(verbatim: MainWindowStrings.Loading.welcomeTitle)
				.font(.largeTitle)
			Text(verbatim: MainWindowStrings.Loading.welcomeDescription)
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: 440)
			Button(MainWindowStrings.Loading.continueAction) {
				AppController.shared.menuController?.showOnboardingWindow(nil)
			}
			.keyboardShortcut(.defaultAction)
			.accessibilityLabel(MainWindowStrings.Loading.beginSetup)
		}
		.padding(padding)
	}

	private func progress(reason: String, iconSize: CGFloat, spacing: CGFloat, padding: CGFloat) -> some View {
		VStack(spacing: spacing) {
			applicationIcon(size: iconSize)
			Text(verbatim: MainWindowStrings.Loading.welcomeTitle)
				.font(.largeTitle)
			HStack(spacing: 8) {
				Text(verbatim: reason)
				ProgressView()
					.controlSize(.small)
			}
		}
		.padding(padding)
	}

	private func applicationIcon(size: CGFloat) -> some View {
		Image(nsImage: NSApp.applicationIconImage)
			.resizable()
			.scaledToFit()
			.frame(width: size, height: size)
			.accessibilityHidden(true)
	}
}
