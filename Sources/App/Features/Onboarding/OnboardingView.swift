// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

struct OnboardingScene: Scene {
	var body: some Scene {
		WindowGroup(
			String(localized: .Onboarding.windowChromeWelcomeToGlasstual),
			id: ApplicationSceneID.onboarding,
			for: SingletonSceneValue.self
		) { _ in
			OnboardingSceneRoot()
		} defaultValue: { .instance }
			.windowResizability(.contentMinSize)
			.windowStyle(.hiddenTitleBar)
	}
}

private struct OnboardingSceneRoot: View {
	@Environment(\.dismissWindow) private var dismissWindow
	@State private var model = OnboardingModel()

	var body: some View {
		OnboardingView(
			model: model,
			applicationIcon: Image(nsImage: NSApp.applicationIconImage),
			dismiss: { dismissWindow(id: ApplicationSceneID.onboarding) }
		)
		/* The window keeps its close button even with the title bar hidden.
		 Closing it applies nothing, but it still records that onboarding was
		 answered — leaving it unmarked is what made the window come back at
		 every launch. A finished flow ignores this. */
		.onDisappear(perform: model.setUpLater)
	}
}

/// The frame the five steps are shown in: the same heading, page indicator and
/// buttons whichever step is up.
struct OnboardingView: View {
	@Bindable var model: OnboardingModel
	let applicationIcon: Image
	let dismiss: () -> Void

	/// Sliding a full panel across the window is exactly the motion Reduce
	/// Motion asks applications to stop making.
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		VStack(spacing: 0) {
			header

			Group {
				if model.isCompleting {
					OnboardingCompletionProgress()
				} else {
					ScrollView {
						stepContent
							.padding(.horizontal, 32)
							.padding(.bottom, UISpacing.loose)
					}
					.scrollBounceBehavior(.basedOnSize)
					.id(model.currentStep)
					.transition(
						reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
					)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			Divider()

			footer
		}
		.frame(minWidth: 720, idealWidth: 720, minHeight: 620, idealHeight: 700)
		.animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.currentStep)
		.animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.isCompleting)
		.alert(
			Text(.Onboarding.connectionUnavailable),
			isPresented: $model.isCompletionFailurePresented
		) {
			Button(PromptStrings.Action.confirmation, role: .cancel) {}
		} message: {
			Text(.Onboarding.connectionUnavailableRecovery)
		}
	}

	private var header: some View {
		VStack(spacing: 6) {
			applicationIcon
				.resizable()
				.scaledToFit()
				.frame(width: 72, height: 72)
				.accessibilityHidden(true)

			Text(model.currentStep.title)
				.font(.largeTitle.weight(.bold))
				.contentTransition(.numericText())

			Text(model.currentStep.subtitle)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 560)
		}
		.padding(.top, 24)
		.padding(.bottom, 14)
	}

	@ViewBuilder
	private var stepContent: some View {
		switch model.currentStep {
		case .identity:
			OnboardingIdentityView(model: model, settings: model.settings)
		case .appearance:
			OnboardingAppearanceView(settings: model.settings)
		case .notifications:
			OnboardingNotificationsView(model: model, settings: model.settings)
		case .network:
			OnboardingNetworkView(
				settings: model.settings,
				picker: model.networkPicker,
				confirm: advance
			)
		case .summary:
			OnboardingSummaryView(model: model)
		}
	}

	private var footer: some View {
		HStack {
			/* Onboarding has to be dismissible without answering it, and
			 without it asking again at the next launch. */
			Button(.Onboarding.windowChromeSetUpLater, action: setUpLater)
				.buttonStyle(.borderless)
				.keyboardShortcut(.cancelAction)

			Button(.Onboarding.windowChromeSkip) { model.skip() }
				.buttonStyle(.borderless)
				.disabled(model.currentStep.isSkippable == false)
				.opacity(model.currentStep.isSkippable ? 1 : 0)

			Spacer()

			OnboardingPageIndicator(
				currentStep: model.currentStep.rawValue,
				stepCount: OnboardingStep.allCases.count,
				accessibilityDescription: model.progressDescription
			)

			Spacer()

			Button(.Onboarding.windowChromeBack, action: model.moveBack)
				.disabled(model.isFirstStep)
				.opacity(model.isFirstStep ? 0 : 1)
				.keyboardShortcut(.leftArrow, modifiers: .command)

			Button(model.primaryButtonTitle, action: advance)
				.keyboardShortcut(.defaultAction)
				.disabled(model.isCurrentStepValid == false)
		}
		.disabled(model.isCompleting)
		.padding(UISpacing.loose)
	}

	private func advance() {
		guard model.advance() else { return }

		Task {
			if await model.finish() {
				dismiss()
			}
		}
	}

	private func setUpLater() {
		model.setUpLater()
		dismiss()
	}
}

private struct OnboardingCompletionProgress: View {
	var body: some View {
		ProgressView(.Onboarding.summarySettingThingsUp)
			.progressViewStyle(.circular)
			.controlSize(.large)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

private struct OnboardingPageIndicator: View {
	let currentStep: Int
	let stepCount: Int
	let accessibilityDescription: LocalizedStringResource

	var body: some View {
		HStack(spacing: UISpacing.regular) {
			ForEach(0 ..< stepCount, id: \.self) { step in
				Circle()
					.fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
					.frame(width: 7, height: 7)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(accessibilityDescription))
	}
}
