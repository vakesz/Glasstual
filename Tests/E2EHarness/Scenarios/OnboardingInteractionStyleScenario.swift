import Foundation

/// The welcome flow's interaction step: choosing the conversation style is
/// stored, and from then on Server Properties opens as a command in the
/// message field instead of a window.
struct OnboardingInteractionStyleScenario: Scenario {
	let name = "onboardingInteractionStyle"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.launch(seed: Seed.onboarding(corpora: context.corpora))
		try await context.completeIdentityStep()
		try await context.driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await context.onboardingStep("interaction")
		try await context.driver.button(AXID.onboardingInteractionConversation, inWindow: AXID.onboardingWindow)
		try await context.driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		for next in ["notifications", "network", "summary"] {
			if next != "notifications" {
				try await context.driver.button(AXID.onboardingSkip, inWindow: AXID.onboardingWindow)
			}
			try await context.onboardingStep(next)
		}
		try await context.finishOnboarding()
		try await context.storedSetting(SettingsKey.interactionStyle, "is the conversation style") {
			($0 as? NSNumber)?.intValue == 1
		}
		try await context.quit(peerSeesQuit: false)
	}
}
