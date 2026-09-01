/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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

	@Test("Onboarding no longer loads a nib")
	func noNibIsShipped() {
		#expect(Bundle.main.path(forResource: "TDCOnboardingWindow", ofType: "nib") == nil)
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
		#expect(server.serverAddress == "irc.example.org")
		#expect(server.serverPort == 6697)
		#expect(server.prefersSecuredConnection)
	}
}
