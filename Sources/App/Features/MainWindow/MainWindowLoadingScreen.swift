/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Observation
import SwiftUI

@Observable
private final class MainWindowLoadingModel {
	enum Content: Equatable {
		case hidden
		case welcome
		case progress(String)
	}

	var content = Content.hidden
}

private struct MainWindowLoadingContent: View {
	@Bindable var model: MainWindowLoadingModel

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

@MainActor
public final class MainWindowLoadingScreenView: NSVisualEffectView {
	private let model = MainWindowLoadingModel()

	public var viewIsVisible: Bool {
		isHidden == false
	}

	override public init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		material = .underWindowBackground
		blendingMode = .withinWindow
		state = .followsWindowActiveState
		isHidden = true

		let host = NSHostingController(rootView: MainWindowLoadingContent(model: model)).view
		host.translatesAutoresizingMaskIntoConstraints = false
		addSubview(host)
		NSLayoutConstraint.activate([
			host.leadingAnchor.constraint(equalTo: leadingAnchor),
			host.trailingAnchor.constraint(equalTo: trailingAnchor),
			host.topAnchor.constraint(equalTo: topAnchor),
			host.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("MainWindowLoadingScreenView is programmatic")
	}

	public func configure() {}

	public func showWelcomeAddServerView() {
		show(.welcome)
	}

	public func showProgressView(withReason reason: String) {
		show(.progress(reason))
	}

	public func setProgressViewReason(_ reason: String) {
		guard case .progress = model.content else { return }
		model.content = .progress(reason)
	}

	public func hide() {
		hideAnimated(false)
	}

	public func hideAnimated() {
		hideAnimated(true)
	}

	public func hideAnimated(_ animated: Bool) {
		guard isHidden == false else { return }
		enableBackgroundControlsStepOne()

		let finish: @MainActor () -> Void = { [weak self] in
			guard let self else { return }
			model.content = .hidden
			isHidden = true
			alphaValue = 1
			enableBackgroundControlsStepTwo()
		}

		guard animated else {
			finish()
			return
		}

		Task { @MainActor in
			await withCheckedContinuation { continuation in
				NSAnimationContext.runAnimationGroup { context in
					context.duration = 0.25
					self.animator().alphaValue = 0
				} completionHandler: {
					continuation.resume()
				}
			}
			finish()
		}
	}

	private func show(_ content: MainWindowLoadingModel.Content) {
		model.content = content
		disableBackgroundControlsStepOne()
		alphaValue = 1
		isHidden = false
		disableBackgroundControlsStepTwo()
	}

	private func disableBackgroundControlsStepOne() {
		mainWindow?.contentSplitViewController.view.isHidden = true
	}

	private func disableBackgroundControlsStepTwo() {
		mainWindow?.inputTextField.isEditable = false
		mainWindow?.inputTextField.isSelectable = false
	}

	private func enableBackgroundControlsStepOne() {
		mainWindow?.contentSplitViewController.view.isHidden = false
	}

	private func enableBackgroundControlsStepTwo() {
		mainWindow?.inputTextField.isEditable = true
		mainWindow?.inputTextField.isSelectable = true
	}
}
