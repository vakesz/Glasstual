import ApplicationServices
import Foundation

/// First launch: the welcome flow sets up the identity and a custom loopback
/// server, the new network registers, and a relaunch neither shows the flow
/// again nor connects by itself.
struct OnboardingFinishScenario: Scenario {
	let name = "onboardingFinish"
	let budget = Duration.seconds(180)
	/// The custom server is named after its address.
	private let network = "127.0.0.1"

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.startPeer(.onboardingFinish)
		try await context.launch(seed: Seed.onboarding(corpora: context.corpora), keepsState: true)
		try await context.completeIdentityStep()
		try await context.driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await context.onboardingStep("interaction")
		try await context.driver.button(AXID.onboardingInteractionDialogs, inWindow: AXID.onboardingWindow)
		try await context.driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await context.onboardingStep("notifications")
		/* Continue here asks macOS for notification permission, and Finish
		 waits for the answer: a system prompt the harness must not answer for
		 the person. Skip leaves the permission alone. */
		try await context.driver.button(AXID.onboardingSkip, inWindow: AXID.onboardingWindow)
		try await context.onboardingStep("network")
		try await context.driver.select(AXID.networkPickerCustomServer) {
			try context.driver.element(AXID.networkPickerList, inWindow: AXID.onboardingWindow)
		}
		try await context.driver.fill(AXID.networkAddress, inWindow: AXID.onboardingWindow, with: "127.0.0.1")
		try await context.driver.fill(AXID.networkPort, inWindow: AXID.onboardingWindow, with: String(peer.port))
		try await context.driver.toggle(AXID.onboardingNetworkTLS, inWindow: AXID.onboardingWindow, to: false)
		try await context.driver.toggle(AXID.onboardingConnectWhenFinished, inWindow: AXID.onboardingWindow, to: false)
		try await context.driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await context.finishOnboarding()

		try await context.server(AXID.RowState.disconnected, network: network)
		try await context.connect()
		try await context.awaitRegistered(network: network)
		try await context.requireIdentityInSettings()
		try await context.quit(peerSeesQuit: true)
		try context.requireStandardRegistration(attempt: 1)

		try await context.relaunchAfterOnboarding()
		try await context.server(AXID.RowState.disconnected, network: network)
		try await context.requireIdentityInSettings()
		try context.requireOnboardingDismissed()
		try await context.quit(peerSeesQuit: false)
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("The relaunch connected to the onboarded network by itself")
		}
	}
}

extension ScenarioContext {
	/// Waits for the welcome window's step `name`.
	func onboardingStep(_ name: String) async throws {
		try await until("onboarding step \(name)") {
			try driver.element(AXID.onboardingStep(name), inWindow: AXID.onboardingWindow) != nil
		}
	}

	/// Fills the identity step with the synthetic identity and continues to
	/// the appearance step.
	func completeIdentityStep() async throws {
		try await onboardingStep("identity")
		try await driver.fill(AXID.onboardingNickname, inWindow: AXID.onboardingWindow, with: "e2euser")
		try await driver.fill(AXID.onboardingRealName, inWindow: AXID.onboardingWindow, with: "Synthetic E2E User")
		try await driver.fill(AXID.onboardingAlternateNickname, inWindow: AXID.onboardingWindow, with: "e2ealternate")
		try await driver.button(AXID.onboardingContinue, inWindow: AXID.onboardingWindow)
		try await onboardingStep("appearance")
	}

	/// On the summary step: checks the summary names the nickname, presses
	/// Finish and waits for the main window to replace the welcome window.
	func finishOnboarding() async throws {
		try await onboardingStep("summary")
		try await until("summary names the synthetic nickname") {
			guard let summary = try driver.element(AXID.onboardingSummary, inWindow: AXID.onboardingWindow) else {
				return false
			}
			let text = try [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
				.compactMap { try driver.string(summary, $0) }.joined(separator: "\n")
			return text.contains("e2euser")
		}
		try await driver.button(AXID.onboardingFinish, inWindow: AXID.onboardingWindow)
		try await until("welcome window closes and the main window is up") {
			try driver.window(AXID.onboardingWindow) == nil && driver.window(AXID.mainWindow) != nil
		}
	}

	/// The identity the flow set is what Settings shows.
	func requireIdentityInSettings() async throws {
		try requireOnboardingDismissed()
		try await openSettings()
		try await selectSettingsPage("defaultIdentity")
		try await until("Settings shows the synthetic identity") {
			guard let nickname = try driver.element(AXID.settingsField(SettingsKey.nickname), inWindow: AXID.settingsWindow),
			      let realName = try driver.element(AXID.settingsField(SettingsKey.realName), inWindow: AXID.settingsWindow)
			else { return false }
			return try driver.value(nickname) == "e2euser" && driver.value(realName) == "Synthetic E2E User"
		}
		try await close(window: AXID.settingsWindow)
		try requireOnboardingDismissed()
	}

	func requireOnboardingDismissed() throws {
		guard try driver.window(AXID.onboardingWindow) == nil else {
			throw HarnessFailure.assertion("Completed onboarding was presented again")
		}
	}

	/// Relaunches against what the first launch kept and waits for the main
	/// window, requiring a new process.
	func relaunchAfterOnboarding() async throws {
		let first = try current
		guard first.exitedCleanly else { throw HarnessFailure.assertion("The first launch did not quit cleanly") }
		try await launch(seed: nil)
		guard try current.pid != first.pid else {
			throw HarnessFailure.assertion("The relaunch did not start a new process")
		}
		try await until("main window after relaunch") { try driver.window(AXID.mainWindow) != nil }
	}
}
