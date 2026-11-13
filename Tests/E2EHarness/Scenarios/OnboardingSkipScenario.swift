import Foundation

/// First launch: the welcome flow with every optional step skipped still
/// records the identity and finishes, and a relaunch does not show it again.
struct OnboardingSkipScenario: Scenario {
	let name = "onboardingSkip"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.launch(seed: Seed.onboarding(corpora: context.corpora), keepsState: true)
		try await context.completeIdentityStep()
		for next in ["interaction", "notifications", "network", "summary"] {
			try await context.driver.button(AXID.onboardingSkip, inWindow: AXID.onboardingWindow)
			try await context.onboardingStep(next)
		}
		try await context.finishOnboarding()
		try await context.requireIdentityInSettings()
		try await context.quit(peerSeesQuit: false)

		try await context.relaunchAfterOnboarding()
		try await context.requireIdentityInSettings()
		try await context.quit(peerSeesQuit: false)
	}
}
