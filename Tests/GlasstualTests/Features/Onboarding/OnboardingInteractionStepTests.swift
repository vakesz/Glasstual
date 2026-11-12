// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing
import UserNotifications

/** The onboarding step that asks how Glasstual asks. It sits after Look and
 Feel, can be skipped, and writes the setting only when accepted. */
@MainActor
@Suite("Onboarding interaction step")
struct OnboardingInteractionStepTests {
	private func model() -> OnboardingModel {
		let settings = OnboardingSettings()
		settings.identity.nickname = "alice"
		settings.identity.realName = "Alice Example"
		return OnboardingModel(
			settings: settings,
			notificationAuthorization: OnboardingNotificationAuthorization(currentStatus: { .notDetermined }, request: { true }),
			markCompleted: {}
		)
	}

	private func walk(_ model: OnboardingModel, to step: OnboardingStep) {
		while model.currentStep != step {
			#expect(model.advance() == false)
		}
	}

	@Test("The step comes right after Look and Feel and before Notifications")
	func order() {
		#expect(OnboardingStep.allCases == [.identity, .appearance, .interaction, .notifications, .network, .summary])
		#expect(OnboardingStep.interaction.isSkippable)
	}

	/// The step is two previews and a note, so the previews take the room the
	/// shared window height leaves rather than stopping halfway down it.
	@Test("A preview takes its share of the step's height, between the smallest and largest it is drawn at")
	func previewHeightFollowsTheStepHeight() {
		#expect(OnboardingInteractionView.previewHeight(forAvailableHeight: 0) == OnboardingPreviewMetrics.minimumHeight)
		#expect(OnboardingInteractionView.previewHeight(forAvailableHeight: 400) == 240)
		#expect(OnboardingInteractionView.previewHeight(forAvailableHeight: 900) == 280)
	}

	@Test("Continuing accepts the choice; skipping drops it")
	func acceptAndSkip() {
		let model = model()
		walk(model, to: .interaction)
		model.settings.interaction = .conversation

		#expect(model.advance() == false)
		#expect(model.accepted.interaction == .conversation)

		model.moveBack()
		model.skip()
		#expect(model.currentStep == .notifications)
		#expect(model.accepted.interaction == nil)
	}

	@Test("Finishing writes the style only when the step was accepted", arguments: [true, false])
	func finishWritesOnlyWhenAccepted(_ accepts: Bool) async {
		let style = SettingsKeys.Interaction.style
		let nickname = SettingsKeys.Identity.nickname
		let realName = SettingsKeys.Identity.realName
		let saved = (style.storedValue, nickname.storedValue, realName.storedValue)
		defer {
			style.storedValue = saved.0
			nickname.storedValue = saved.1
			realName.storedValue = saved.2
		}
		style.value = .dialogs
		let model = model()
		walk(model, to: .appearance)
		model.skip()
		model.settings.interaction = .conversation
		if accepts {
			_ = model.advance()
		} else {
			model.skip()
		}
		model.skip()
		model.skip()

		#expect(model.currentStep == .summary)
		#expect(await model.finish())
		#expect(style.value == (accepts ? .conversation : .dialogs))
	}

	@Test("Each style has a caption and a stable identifier")
	func captionsAndIdentifiers() {
		for style in InteractionStyle.allCases {
			#expect(String(localized: style.onboardingCaption).isEmpty == false)
		}
		#expect(InteractionStyle.dialogs.onboardingIdentifier == "onboarding-interaction-dialogs")
		#expect(InteractionStyle.conversation.onboardingIdentifier == "onboarding-interaction-conversation")
	}
}
