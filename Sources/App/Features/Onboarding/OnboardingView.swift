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

/// The frame the steps are shown in: the welcome heading on the first, a
/// title on the others, and the same buttons whichever step is up.
struct OnboardingView: View {
	@Bindable var model: OnboardingModel
	let applicationIcon: Image
	let dismiss: () -> Void

	/// Sliding a full panel across the window is exactly the motion Reduce
	/// Motion asks applications to stop making.
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	/// The height between the heading and the buttons, which every step is
	/// shown in. The window's height is the same for all of them.
	@State private var stepAreaHeight: CGFloat = 0

	var body: some View {
		VStack(spacing: 0) {
			header

			Group {
				if model.isCompleting {
					OnboardingCompletionProgress()
				} else {
					ScrollView {
						stepContent
							.padding(.horizontal, UISpacing.loose * 2)
							.padding(.bottom, Self.stepBottomPadding)
					}
					.scrollBounceBehavior(.basedOnSize)
					/* No page dots: a Mac setup flow does not draw them. Where the
					 step falls in the flow is said to VoiceOver instead. */
					.accessibilityLabel(Text(model.progressDescription))
					.accessibilityIdentifier(AccessibilityIdentifier.onboardingStep(String(describing: model.currentStep)))
					.id(model.currentStep)
					.transition(
						reduceMotion ? .opacity : .asymmetric(
							insertion: .opacity.combined(with: .move(edge: model.movesForward ? .trailing : .leading)),
							removal: .opacity.combined(with: .move(edge: model.movesForward ? .leading : .trailing))
						)
					)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stepAreaHeight = $0 }

			Divider()

			footer
		}
		.frame(minWidth: 600, idealWidth: 620, minHeight: 540, idealHeight: 620)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier(AccessibilityIdentifier.onboardingWindow)
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

	/// What a step keeps clear beneath itself, above the buttons' divider.
	private static let stepBottomPadding = UISpacing.loose

	/// The icon and large title welcome the reader on the first step only;
	/// the steps after it carry a plain title, as a setup assistant's do.
	private var header: some View {
		VStack(spacing: UISpacing.snug) {
			if model.isFirstStep {
				applicationIcon
					.resizable()
					.scaledToFit()
					.frame(width: 64, height: 64)
					.accessibilityHidden(true)
			}

			Text(model.currentStep.title)
				.font(model.isFirstStep ? .largeTitle.weight(.bold) : .title2.weight(.bold))
				.multilineTextAlignment(.center)
				.accessibilityAddTraits(.isHeader)

			Text(model.currentStep.subtitle)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 480)
		}
		.padding(.horizontal, UISpacing.loose * 2)
		.padding(.top, model.isFirstStep ? UISpacing.spacious : UISpacing.loose)
		.padding(.bottom, UISpacing.wide)
	}

	@ViewBuilder
	private var stepContent: some View {
		switch model.currentStep {
		case .identity:
			OnboardingIdentityView(model: model, settings: model.settings)
		case .appearance:
			OnboardingAppearanceView(settings: model.settings)
		case .interaction:
			OnboardingInteractionView(
				settings: model.settings,
				availableHeight: max(0, stepAreaHeight - Self.stepBottomPadding)
			)
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

	/// Set Up Later on the leading edge; Skip, Back and Continue together on
	/// the trailing edge, Continue the default button.
	private var footer: some View {
		HStack {
			/* Onboarding has to be dismissible without answering it, and
			 without it asking again at the next launch. */
			Button(.Onboarding.windowChromeSetUpLater, action: setUpLater)
				.buttonStyle(.borderless)
				.keyboardShortcut(.cancelAction)

			Spacer()

			if model.currentStep.isSkippable {
				Button(.Onboarding.windowChromeSkip) { model.skip() }
					.accessibilityIdentifier(AccessibilityIdentifier.onboardingSkip)
			}

			if model.isFirstStep == false {
				Button(.Onboarding.windowChromeBack, action: model.moveBack)
					.keyboardShortcut(.leftArrow, modifiers: .command)
					.accessibilityIdentifier(AccessibilityIdentifier.onboardingBack)
			}

			Button(model.primaryButtonTitle, action: advance)
				.keyboardShortcut(.defaultAction)
				.disabled(model.isCurrentStepValid == false)
				.accessibilityIdentifier(
					model.isLastStep ? AccessibilityIdentifier.onboardingFinish : AccessibilityIdentifier.onboardingContinue
				)
		}
		.disabled(model.isCompleting)
		.padding(UISpacing.spacious)
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
