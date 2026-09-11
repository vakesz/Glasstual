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
	private var testAuthorization: OnboardingNotificationAuthorization {
		OnboardingNotificationAuthorization(
			currentStatus: { .notDetermined },
			request: { true }
		)
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

		_ = model.continueFlow()
		_ = model.continueFlow()
		_ = model.continueFlow()

		#expect(model.currentStep == .network)

		/* The prompt is answered in a task of its own, so the answer lands after
		 the step has moved on. */
		for _ in 0 ..< 200 where refreshes.count == 0 {
			try? await Task.sleep(for: .milliseconds(5))
		}

		#expect(refreshes.count == 1)
	}

	@Test("Identity validation keeps the user on the first step")
	func invalidIdentityDoesNotAdvance() {
		let settings = OnboardingSettings()
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)

		#expect(model.continueFlow() == false)
		#expect(model.currentStep == .identity)
		#expect(model.isValidationPresented)
	}

	@Test("A valid identity advances and is normalized")
	func validIdentityAdvances() {
		let settings = OnboardingSettings()
		settings.nickname = "  alice  "
		settings.realName = "  Alice Example  "
		settings.alternateNickname = "  alice_  "
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)

		#expect(model.continueFlow() == false)
		#expect(model.currentStep == .appearance)
		#expect(settings.nickname == "alice")
		#expect(settings.realName == "Alice Example")
		#expect(settings.alternateNickname == "alice_")
	}

	@Test("Back navigation returns to the previous step")
	func backNavigation() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		_ = model.continueFlow()

		model.moveBack()

		#expect(model.currentStep == .identity)
	}

	@Test("Finishing without a network remains a supported choice")
	func networkIsOptional() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		_ = model.continueFlow()
		_ = model.continueFlow()
		_ = model.continueFlow()

		#expect(model.currentStep == .network)
		#expect(model.continueFlow())
		#expect(settings.clientConfig == nil)
		#expect(settings.channelsToJoin.isEmpty)
	}

	@Test("A custom server produces a typed client configuration")
	func customServerConfiguration() throws {
		let model = NetworkPickerModel()
		model.updateDefaultNickname("alice")
		model.selectionID = model.customOption.id
		model.serverAddress = "IRC.EXAMPLE.ORG"
		model.serverPort = "6697"
		model.accountPassword = "secret"

		try model.validate()
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

	@Test("Turning SASL off persists the choice without deleting NickServ credentials")
	func saslChoiceDoesNotDeleteCredentials() throws {
		let picker = NetworkPickerModel()
		picker.selectionID = picker.customOption.id
		picker.serverAddress = "irc.example.test"
		picker.setAccountName("account")
		picker.accountPassword = "secret"
		picker.usesSASL = false
		let config = try #require(picker.clientConfig())
		#expect(config.usesSASL == false)
		#expect(config.pendingNicknamePassword == .set("secret"))
		#expect(config.username == "account")
		picker.selectionID = picker.customOption.id
		#expect(picker.accountPassword == "secret")
		#expect(picker.accountName == "account")
	}

	@Test("Skip saves accepted identity and visible appearance once without creating a network")
	func skipPersistsOnce() {
		let settings = OnboardingSettings()
		settings.nickname = " alice "
		settings.realName = " Alice Example "
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		var saves = 0
		var completed = 0
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Skip created a connection"); return false },
			applySettings: { accepted in
				#expect(accepted.acceptedIdentity?.nickname == "alice")
				#expect(accepted.acceptedIdentity?.realName == "Alice Example")
				#expect(accepted.acceptedAppearance?.theme.fontSize == 15)
				#expect(accepted.acceptedNotifications == nil)
				saves += 1
			},
			markCompleted: { completed += 1 }
		)
		#expect(session.skipRemainingSteps() == false)
		#expect(session.continueFlow() == false)
		settings.textSize = .large
		#expect(session.skipRemainingSteps())
		#expect(session.skipRemainingSteps())
		#expect(session.cancel())
		#expect(saves == 1)
		#expect(completed == 1)
	}

	/** Cancelling on the very first step is still an answer.

	 It used to persist nothing at all, so onboarding re-presented itself at
	 every launch with no way to stop it: nothing is applied, but the fact that
	 the user closed it is recorded. */
	@Test("Cancel without accepted identity applies nothing and still completes")
	func cancelBeforeIdentity() {
		let model = OnboardingModel(settings: OnboardingSettings(), notificationAuthorization: testAuthorization)
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Cancel created a connection"); return false },
			applySettings: { _ in Issue.record("Unaccepted settings were saved") },
			markCompleted: { events.append("complete") }
		)

		#expect(session.cancel())
		#expect(session.cancel())
		#expect(events == ["complete"])
	}

	@Test("Set Up Later applies nothing and does not come back")
	func setUpLaterCompletesWithoutApplying() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Set Up Later created a connection"); return false },
			applySettings: { _ in Issue.record("Set Up Later saved settings") },
			markCompleted: { events.append("complete") }
		)
		_ = session.continueFlow()

		#expect(session.setUpLater())
		#expect(events == ["complete"])
	}

	@Test("Cancel preserves the last accepted values rather than later edits")
	func cancelKeepsAcceptedValues() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		var saves = 0
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Cancel created a connection"); return false },
			applySettings: { accepted in
				#expect(accepted.acceptedIdentity?.nickname == "alice")
				#expect(accepted.acceptedAppearance?.theme.fontSize == 15)
				saves += 1
			},
			markCompleted: {}
		)
		_ = session.continueFlow()
		settings.textSize = .large
		_ = session.continueFlow()
		session.moveBack()
		settings.textSize = .small
		session.moveBack()
		settings.nickname = "invalid nickname"
		#expect(session.cancel())
		#expect(saves == 1)
	}

	/** Closing the window used to leave onboarding unfinished, so it came back
	 at every launch however far the user had got. It is a Cancel: the accepted
	 steps are saved and onboarding is marked complete, exactly once. */
	@Test("Closing the window behaves like Cancel")
	func windowCloseBehavesLikeCancel() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Closing the window created a connection"); return false },
			applySettings: { accepted in
				#expect(accepted.acceptedIdentity?.nickname == "alice")
				events.append("save")
			},
			markCompleted: { events.append("complete") }
		)
		_ = session.continueFlow()

		session.windowDidClose()
		session.windowDidClose()

		#expect(events == ["save", "complete"])
		#expect(settings.clientConfig == nil)
		#expect(settings.channelsToJoin.isEmpty)
	}

	/// Nothing was accepted, so there is nothing to apply — but the window was
	/// closed on purpose, and asking again at the next launch is what the user
	/// just declined.
	@Test("Closing the window before the first step applies nothing and completes")
	func windowCloseBeforeIdentityAppliesNothing() {
		let model = OnboardingModel(settings: OnboardingSettings(), notificationAuthorization: testAuthorization)
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Closing the window created a connection"); return false },
			applySettings: { _ in Issue.record("Unaccepted settings were saved") },
			markCompleted: { events.append("complete") }
		)

		session.windowDidClose()

		#expect(model.acceptedIdentity == nil)
		#expect(events == ["complete"])
	}

	@Test("Every appearance the picker offers has a title of its own")
	func appearanceTitlesCoverEveryCase() {
		let titles = PreferredAppearance.allCases.map(OnboardingStrings.Appearance.interfaceStyleTitle)

		#expect(titles.count == PreferredAppearance.allCases.count)
		#expect(Set(titles).count == titles.count)
		#expect(titles.contains(where: \.isEmpty) == false)
	}

	@Test("Finish without a network saves preferences and completes once")
	func sessionFinishesWithoutNetwork() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		var events: [String] = []
		let session = OnboardingSession(
			model: model,
			createConnection: { _, _ in Issue.record("Unexpected connection"); return false },
			applySettings: { _ in events.append("save") },
			markCompleted: { events.append("complete") }
		)
		for _ in 0 ..< 3 {
			#expect(session.continueFlow() == false)
		}
		#expect(events.isEmpty)
		#expect(session.continueFlow())
		#expect(session.continueFlow())
		#expect(events == ["save", "complete"])
	}

	@Test("Failed client creation remains retryable and never marks completion")
	func failedFinishCanRetry() {
		let settings = OnboardingSettings()
		settings.nickname = "alice"
		settings.realName = "Alice"
		settings.alternateNickname = "alice_"
		settings.connectWhenFinished = false
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)
		model.networkPicker.selectionID = model.networkPicker.customOption.id
		model.networkPicker.serverAddress = "irc.example.test"
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
		for _ in 0 ..< 3 {
			_ = session.continueFlow()
		}
		#expect(session.continueFlow() == false)
		#expect(model.isValidationPresented)
		#expect(events.isEmpty)
		#expect(session.continueFlow())
		#expect(session.continueFlow())
		#expect(attempts == 2)
		#expect(events == ["save", "complete"])
	}
}
