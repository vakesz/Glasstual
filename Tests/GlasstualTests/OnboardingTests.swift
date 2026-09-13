/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
@testable import Glasstual
import Testing
import UserNotifications

@MainActor
@Suite("SwiftUI onboarding")
struct OnboardingTests {
	/// The live value reaches for the application's notification controller, so
	/// the tests supply their own answer and their own sound-delivery hook.
	private var testAuthorization: OnboardingNotificationAuthorization {
		var authorization = OnboardingNotificationAuthorization(
			currentStatus: { .notDetermined },
			request: { true }
		)
		authorization.soundDeliveryDidChange = {}
		return authorization
	}

	private func identifiedModel(nickname: String = "alice") -> OnboardingModel {
		let settings = OnboardingSettings()
		settings.nickname = nickname
		return OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
	}

	/// Walks to `step` by accepting everything in front of it.
	private func advance(_ model: OnboardingModel, to step: OnboardingStep) {
		while model.currentStep != step {
			#expect(model.advance() == false)
		}
	}

	@MainActor
	private final class SoundDeliveryRefreshes {
		var count = 0
	}

	/** Whether the system will play a notification's sound follows from the
	 permission answer, and the notification controller reads it once at launch —
	 which on a first launch is before the onboarding window has asked. Nothing
	 told it the answer had arrived, so the rest of that session had the
	 application playing every sound itself. */
	@Test("Granting permission during onboarding has the sound delivery read again")
	func grantingPermissionRefreshesSoundDelivery() async {
		let refreshes = SoundDeliveryRefreshes()
		var authorization = testAuthorization
		authorization.soundDeliveryDidChange = { refreshes.count += 1 }
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: authorization)

		advance(model, to: .network)

		/* The prompt is answered in a task of its own, and the window must not
		 close while the system is still showing it. */
		await model.completePendingWork()

		#expect(refreshes.count == 1)
	}

	/// Skipping the notifications step is a refusal, so it must not raise the
	/// system permission prompt either.
	@Test("Skipping the notifications step asks for no permission")
	func skippingNotificationsAsksForNothing() async {
		let refreshes = SoundDeliveryRefreshes()
		var authorization = testAuthorization
		authorization.soundDeliveryDidChange = { refreshes.count += 1 }
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: authorization)

		advance(model, to: .notifications)
		model.skip()

		#expect(model.currentStep == .network)
		await model.completePendingWork()
		#expect(refreshes.count == 0)
		#expect(model.acceptedNotifications == nil)
	}

	@Test("An unusable nickname is reported beside the field and blocks Continue")
	func invalidIdentityIsReportedInline() {
		let model = identifiedModel(nickname: "")

		#expect(model.nicknameProblem == OnboardingStrings.Identity.nicknameRequired)
		#expect(model.isCurrentStepValid == false)
		#expect(model.advance() == false)
		#expect(model.currentStep == .identity)

		model.settings.nickname = "not a nickname"
		#expect(model.nicknameProblem == CommonValidationStrings.invalidNickname)

		model.settings.nickname = "alice"
		model.settings.alternateNickname = "not a nickname"
		#expect(model.nicknameProblem == nil)
		#expect(model.alternateNicknameProblem == CommonValidationStrings.invalidNickname)
		#expect(model.isCurrentStepValid == false)

		model.settings.alternateNickname = ""
		model.settings.realName = "Alice\nExample"
		#expect(model.realNameProblem == CommonValidationStrings.singleLineRequired)
		#expect(model.isCurrentStepValid == false)
	}

	@Test("A valid identity advances and is normalized")
	func validIdentityAdvances() {
		let settings = OnboardingSettings()
		settings.nickname = "  alice  "
		settings.realName = "  Alice Example  "
		settings.alternateNickname = "  alice_  "
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)

		#expect(model.advance() == false)
		#expect(model.currentStep == .appearance)
		#expect(settings.nickname == "alice")
		#expect(settings.realName == "Alice Example")
		#expect(settings.alternateNickname == "alice_")
	}

	@Test("Back navigation returns to the previous step")
	func backNavigation() {
		let model = identifiedModel()
		_ = model.advance()

		model.moveBack()

		#expect(model.currentStep == .identity)
	}

	/** Skip used to finish the whole flow, which is not what the word means.

	 It now passes over exactly one step, and drops whatever an earlier visit to
	 that step had accepted so a skipped step changes no preference. */
	@Test("Skip passes over one step and drops what that step accepted")
	func skipAdvancesOneStepAndForgetsIt() {
		let model = identifiedModel()

		advance(model, to: .appearance)
		model.settings.textSize = .large
		#expect(model.advance() == false)
		#expect(model.currentStep == .notifications)
		#expect(model.acceptedAppearance?.textSize == .large)

		model.moveBack()
		model.skip()

		#expect(model.currentStep == .notifications)
		#expect(model.acceptedAppearance == nil)
	}

	@Test("Identity and the summary cannot be skipped")
	func requiredStepsRefuseSkip() {
		let model = identifiedModel()

		model.skip()
		#expect(model.currentStep == .identity)

		advance(model, to: .summary)
		model.skip()
		#expect(model.currentStep == .summary)
		#expect(model.isLastStep)
	}

	@Test("Finishing without a network remains a supported choice")
	func networkIsOptional() {
		let model = identifiedModel()

		advance(model, to: .summary)

		#expect(model.advance())
		#expect(model.settings.clientConfig == nil)
		#expect(model.settings.channelsToJoin.isEmpty)
	}

	@Test("A custom server produces a typed client configuration")
	func customServerConfiguration() throws {
		let model = NetworkPickerModel()
		model.updateDefaultNickname("alice")
		model.selection = .customServer
		model.draft.serverAddress = "IRC.EXAMPLE.ORG"
		model.draft.serverPort = 6697
		model.draft.accountPassword = "secret"

		#expect(model.isValid)
		let config = try #require(model.clientConfig())
		let server = try #require(config.serverList.first)

		#expect(config.connectionName == "irc.example.org")
		#expect(config.username == "alice")
		#expect(config.nicknamePassword == "secret")
		#expect(config.usesSASL)
		#expect(server.serverAddress == "irc.example.org")
		#expect(server.serverPort == 6697)
		#expect(server.prefersSecuredConnection)
	}

	/// The port is a number all the way through, so the only value the field can
	/// hold that no server can listen on is zero.
	@Test("Network details are reported field by field")
	func networkProblemsAreReportedPerField() {
		let picker = NetworkPickerModel()

		#expect(picker.isValid)
		#expect(picker.serverAddressProblem == nil)

		picker.selection = .customServer
		#expect(picker.serverAddressProblem == CommonValidationStrings.invalidServerAddress)
		#expect(picker.isValid == false)

		picker.draft.serverAddress = "irc.example.test"
		picker.draft.serverPort = 0
		#expect(picker.serverPortProblem == OnboardingStrings.NetworkPicker.invalidPort)

		picker.draft.serverPort = 6697
		picker.draft.accountPassword = "secret"
		picker.setAccountName("not a username")
		#expect(picker.accountProblem == OnboardingStrings.NetworkPicker.invalidAccount)

		picker.setAccountName("alice")
		#expect(picker.isValid)
	}

	@Test("Turning SASL off persists the choice without deleting NickServ credentials")
	func saslChoiceDoesNotDeleteCredentials() throws {
		let picker = NetworkPickerModel()
		picker.selection = .customServer
		picker.draft.serverAddress = "irc.example.test"
		picker.setAccountName("account")
		picker.draft.accountPassword = "secret"
		picker.draft.usesSASL = false
		let config = try #require(picker.clientConfig())
		#expect(config.usesSASL == false)
		#expect(config.pendingNicknamePassword == .set("secret"))
		#expect(config.username == "account")
		picker.selection = .customServer
		#expect(picker.draft.accountPassword == "secret")
		#expect(picker.draft.accountName == "account")
	}

	/** "Set Up Later" is the one way out that applies nothing.

	 It used to share its behaviour with a Cancel button that committed every
	 preference the person had typed on their way past it. */
	@Test("Set Up Later applies nothing and does not come back")
	func setUpLaterCompletesWithoutApplying() {
		let model = identifiedModel()
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Set Up Later created a connection"); return false },
			applySettings: { _ in Issue.record("Set Up Later saved settings") },
			markCompleted: { events.append("complete") }
		)
		_ = model.advance()

		session.setUpLater()
		session.setUpLater()

		#expect(events == ["complete"])
	}

	/** Closing the window used to save everything the person had typed. It is a
	 dismissal, so it applies nothing — but onboarding is still marked answered,
	 because leaving it unmarked is what made it come back at every launch. */
	@Test("Closing the window applies nothing and still completes once")
	func windowCloseAppliesNothing() {
		let model = identifiedModel()
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Closing the window created a connection"); return false },
			applySettings: { _ in Issue.record("Closing the window saved settings") },
			markCompleted: { events.append("complete") }
		)
		advance(model, to: .summary)

		session.setUpLater()

		#expect(events == ["complete"])
		#expect(model.settings.clientConfig == nil)
	}

	@Test("Every appearance the picker offers has a title of its own")
	func appearanceTitlesCoverEveryCase() {
		let titles = PreferredAppearance.allCases.map(OnboardingStrings.Appearance.interfaceStyleTitle)

		#expect(titles.count == PreferredAppearance.allCases.count)
		#expect(Set(titles).count == titles.count)
		#expect(titles.contains(where: \.isEmpty) == false)
	}

	@Test("Finish without a network saves preferences and completes once")
	func sessionFinishesWithoutNetwork() async {
		let model = identifiedModel()
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Unexpected connection"); return false },
			applySettings: { accepted in
				#expect(accepted.acceptedIdentity?.nickname == "alice")
				events.append("save")
			},
			markCompleted: { events.append("complete") }
		)
		advance(model, to: .summary)
		#expect(model.advance())
		#expect(events.isEmpty)

		#expect(await session.finish())
		#expect(await session.finish())

		#expect(events == ["save", "complete"])
		#expect(session.isCompleting == false)
	}

	/// A skipped step leaves its preferences alone, which is the whole reason a
	/// step records what it accepted rather than what its controls show.
	@Test("Only the steps that were accepted are applied")
	func skippedStepsApplyNothing() async {
		let model = identifiedModel()
		var saves = 0
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Unexpected connection"); return false },
			applySettings: { accepted in
				#expect(accepted.acceptedIdentity?.nickname == "alice")
				#expect(accepted.acceptedAppearance == nil)
				#expect(accepted.acceptedNotifications?.highlight == true)
				saves += 1
			},
			markCompleted: {}
		)

		#expect(model.advance() == false)
		model.skip()
		#expect(model.currentStep == .notifications)
		#expect(model.advance() == false)
		model.skip()
		#expect(model.currentStep == .summary)
		#expect(model.advance())

		#expect(await session.finish())
		#expect(saves == 1)
	}

	@Test("Failed client creation remains retryable and never marks completion")
	func failedFinishCanRetry() async {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		settings.realName = "Alice"
		settings.alternateNickname = "alice_"
		settings.connectWhenFinished = false
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		model.networkPicker.selection = .customServer
		model.networkPicker.draft.serverAddress = "irc.example.test"
		var attempts = 0
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { config, connect in
				#expect(config.nickname == "alice")
				#expect(config.realName == "Alice")
				#expect(config.alternateNicknames == ["alice_"])
				#expect(config.autoConnect == false)
				#expect(connect == false)
				attempts += 1
				return attempts > 1
			},
			applySettings: { _ in events.append("save") },
			markCompleted: { events.append("complete") }
		)
		advance(model, to: .summary)
		#expect(model.advance())

		#expect(await session.finish() == false)
		#expect(session.completionFailure == OnboardingStrings.Window.connectionUnavailable)
		#expect(session.isCompletionFailurePresented)
		#expect(events.isEmpty)

		session.isCompletionFailurePresented = false
		#expect(session.completionFailure == nil)
		#expect(await session.finish())
		#expect(attempts == 2)
		#expect(events == ["save", "complete"])
	}
}
