// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
@testable import Glasstual
import Testing
import UserNotifications

@MainActor
@Suite("SwiftUI onboarding")
struct OnboardingTests {
	@Test("Port text blocks Continue without reverting malformed input", arguments: ["", " ", "0", "65536", "-1", "66x7", "1.5", "６６６７"])
	func invalidPortText(_ text: String) {
		let model = identifiedModel()
		advance(model, to: .network)
		model.networkPicker.networks.selection = .customServer
		model.networkPicker.draft.serverAddress = "irc.example.test"
		model.networkPicker.draft.serverPortText = text
		#expect(model.networkPicker.serverPortProblem != nil)
		#expect(!model.isCurrentStepValid)
		#expect(!model.advance())
		#expect(model.currentStep == .network)
		#expect(model.networkPicker.draft.serverPortText == text)
	}

	@Test("TLS toggles exchange standard ports and preserve custom or invalid input")
	func tlsPortExchange() {
		let picker = OnboardingNetworkPickerModel()
		picker.setPrefersSecuredConnection(false)
		#expect(picker.draft.serverPort == 6667)
		picker.setPrefersSecuredConnection(true)
		#expect(picker.draft.serverPort == 6697)
		picker.draft.serverPortText = "7000"
		picker.setPrefersSecuredConnection(false)
		#expect(picker.draft.serverPortText == "7000")
		picker.draft.serverPortText = "invalid"
		picker.setPrefersSecuredConnection(true)
		#expect(picker.draft.serverPortText == "invalid")
	}

	@Test("Back and Continue report their actual navigation direction")
	func navigationDirection() {
		let model = identifiedModel()
		_ = model.advance()
		#expect(model.movesForward)
		model.moveBack()
		#expect(!model.movesForward)
		_ = model.advance()
		#expect(model.movesForward)
	}

	/// The live value asks the system, so the tests supply their own answer.
	private var testAuthorization: OnboardingNotificationAuthorization {
		OnboardingNotificationAuthorization(
			currentStatus: { .notDetermined },
			request: { true }
		)
	}

	/// A model that is past the identity step's rules, with whatever the test
	/// needs to watch standing in for what the model would otherwise reach for.
	private func identifiedModel(
		nickname: String = "alice",
		createConnection: (@MainActor (ServerConfig, Bool) -> Bool)? = nil,
		applySettings: (@MainActor (OnboardingModel) -> Void)? = nil,
		markCompleted: (@MainActor () -> Void)? = nil
	) -> OnboardingModel {
		let settings = OnboardingSettings()
		settings.identity.nickname = nickname
		settings.identity.realName = "Alice Example"
		return OnboardingModel(
			settings: settings,
			notificationAuthorization: testAuthorization,
			createConnection: createConnection,
			applySettings: applySettings,
			markCompleted: markCompleted
		)
	}

	/// Walks to `step` by accepting everything in front of it.
	private func advance(_ model: OnboardingModel, to step: OnboardingStep) {
		while model.currentStep != step {
			#expect(model.advance() == false)
		}
	}

	@MainActor
	private final class PermissionReads {
		var count = 0
	}

	/// The notifications step reads the permission from its view's task. The
	/// model started a second read of its own on every visit to the step.
	@Test("Moving onto the notifications step leaves the permission read to its view")
	func movingOntoNotificationsReadsNothing() async {
		let reads = PermissionReads()
		let authorization = OnboardingNotificationAuthorization(
			currentStatus: { @MainActor in
				reads.count += 1
				return .authorized
			},
			request: { true }
		)
		let settings = OnboardingSettings()
		settings.identity.nickname = "alice"
		settings.identity.realName = "Alice Example"
		let model = OnboardingModel(settings: settings, notificationAuthorization: authorization)

		advance(model, to: .notifications)
		model.moveBack()
		model.skip()
		await model.completePendingWork()

		#expect(model.currentStep == .notifications)
		#expect(reads.count == 0)

		await model.refreshNotificationPermission()

		#expect(reads.count == 1)
		#expect(model.notificationPermissionMessage == .Onboarding.notificationsAreAllowedForGlasstual)
	}

	/// Skipping the notifications step is a refusal, so it must not raise the
	/// system permission prompt either.
	@Test("Skipping the notifications step asks for no permission")
	func skippingNotificationsAsksForNothing() async {
		let settings = OnboardingSettings()
		settings.identity.nickname = "alice"
		settings.identity.realName = "Alice Example"
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)

		advance(model, to: .notifications)
		model.skip()

		#expect(model.currentStep == .network)
		await model.completePendingWork()
		#expect(model.accepted.notifications == nil)
	}

	@Test("Notification permission is requested only when alerts are enabled", arguments: [true, false])
	func notificationPermissionFollowsTheAlertChoice(alertsEnabled: Bool) async {
		let requests = PermissionReads()
		let settings = OnboardingSettings()
		settings.identity.nickname = "alice"
		settings.identity.realName = "Alice Example"
		settings.notifications.notifyAboutMentions = alertsEnabled
		settings.notifications.playSounds = true
		let model = OnboardingModel(
			settings: settings,
			notificationAuthorization: OnboardingNotificationAuthorization(
				currentStatus: { .notDetermined },
				request: { @MainActor in
					requests.count += 1
					return true
				}
			)
		)

		advance(model, to: .notifications)
		#expect(model.advance() == false)
		await model.completePendingWork()

		#expect(requests.count == (alertsEnabled ? 1 : 0))
		#expect(model.accepted.notifications?.notifyAboutMentions == alertsEnabled)
	}

	@Test("An unusable nickname is reported beside the field and blocks Continue")
	func invalidIdentityIsReportedInline() {
		let model = identifiedModel(nickname: "")

		#expect(model.nicknameProblem == String(localized: .Onboarding.stepWelcomeAndIdentityNicknameRequired))
		#expect(model.isCurrentStepValid == false)
		#expect(model.advance() == false)
		#expect(model.currentStep == .identity)

		model.settings.identity.nickname = "not a nickname"
		#expect(model.nicknameProblem == CommonValidationStrings.invalidNickname)

		model.settings.identity.nickname = "alice"
		model.settings.identity.alternateNickname = "not a nickname"
		#expect(model.nicknameProblem == nil)
		#expect(model.alternateNicknameProblem == CommonValidationStrings.invalidNickname)
		#expect(model.isCurrentStepValid == false)

		model.settings.identity.alternateNickname = ""
		model.settings.identity.realName = "Alice\nExample"
		#expect(model.realNameProblem == CommonValidationStrings.invalidRealName)
		#expect(model.isCurrentStepValid == false)
	}

	/** Onboarding accepted an empty real name that the server properties sheet
	 then refused, so the connection it created could not be saved again
	 without first fixing a field onboarding had let through. */
	@Test("A real name the server properties sheet refuses is refused here too", arguments: ["", "   ", "Alice\nExample"])
	func realNameFollowsTheServerPropertiesRule(_ realName: String) {
		let model = identifiedModel()
		model.settings.identity.realName = realName

		#expect(model.realNameProblem == CommonValidationStrings.invalidRealName)
		#expect(model.isCurrentStepValid == false)

		var config = ServerConfig(connectionName: "Libera")
		config.serverList = [ServerEndpoint(serverAddress: "irc.libera.chat", serverPort: 6697)]
		config.nickname = "alice"
		config.username = "alice"
		config.realName = realName
		let sheet = ServerPropertiesModel(config: config)

		#expect(sheet.validationFault?.message == CommonValidationStrings.invalidRealName)
	}

	@Test("A valid identity advances and is normalized")
	func validIdentityAdvances() {
		let settings = OnboardingSettings()
		settings.identity.nickname = "  alice  "
		settings.identity.realName = "  Alice Example  "
		settings.identity.alternateNickname = "  alice_  "
		let model = OnboardingModel(settings: settings, notificationAuthorization: testAuthorization)

		#expect(model.advance() == false)
		#expect(model.currentStep == .appearance)
		#expect(settings.identity.nickname == "alice")
		#expect(settings.identity.realName == "Alice Example")
		#expect(settings.identity.alternateNickname == "alice_")
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
	 that step had accepted so a skipped step changes no setting. */
	@Test("Skip passes over one step and drops what that step accepted")
	func skipAdvancesOneStepAndForgetsIt() {
		let model = identifiedModel()

		advance(model, to: .appearance)
		model.settings.appearance.textSize = .large
		#expect(model.advance() == false)
		#expect(model.currentStep == .notifications)
		#expect(model.accepted.appearance?.textSize == .large)

		model.moveBack()
		model.skip()

		#expect(model.currentStep == .notifications)
		#expect(model.accepted.appearance == nil)
	}

	/** The network step follows the same convention as the other three.

	 It used to write the connection into the settings the steps are editing and
	 nil it out again by hand, which is why the summary had to know that two of
	 its rows were read from somewhere else. */
	@Test("The network step contributes a connection, and Skip drops it")
	func skippingTheNetworkStepDropsItsConnection() throws {
		let model = identifiedModel()

		advance(model, to: .network)
		model.networkPicker.networks.selection = .customServer
		model.networkPicker.draft.serverAddress = "irc.example.test"
		#expect(model.advance() == false)

		let accepted = try #require(model.accepted.network)
		#expect(accepted.serverConfig?.connectionName == "irc.example.test")

		model.moveBack()
		model.skip()

		#expect(model.currentStep == .summary)
		#expect(model.accepted.network == nil)
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
	func networkIsOptional() throws {
		let model = identifiedModel()

		advance(model, to: .summary)

		#expect(model.advance())
		let network = try #require(model.accepted.network)
		#expect(network.serverConfig == nil)
		#expect(network.channelsToJoin.isEmpty)
	}

	@Test("A custom server produces a typed session configuration")
	func customServerConfiguration() throws {
		let model = OnboardingNetworkPickerModel()
		model.updateDefaultNickname("alice")
		model.networks.selection = .customServer
		model.draft.serverAddress = "IRC.EXAMPLE.ORG"
		model.draft.serverPort = 6697
		model.draft.accountPassword = "secret"

		#expect(model.isValid)
		let config = try #require(model.serverConfig())
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
		let picker = OnboardingNetworkPickerModel()

		#expect(picker.isValid)
		#expect(picker.serverAddressProblem == nil)

		picker.networks.selection = .customServer
		#expect(picker.serverAddressProblem == CommonValidationStrings.invalidServerAddress)
		#expect(picker.isValid == false)

		picker.draft.serverAddress = "irc.example.test"
		picker.draft.serverPort = 0
		#expect(picker.serverPortProblem == String(localized: .Onboarding.enterAPortBetween1))

		picker.draft.serverPort = 6697
		picker.draft.accountPassword = "secret"
		picker.setAccountName("not a username")
		#expect(picker.accountProblem == String(localized: .Onboarding.invalidAccount))

		picker.setAccountName("alice")
		#expect(picker.isValid)
	}

	@Test("Turning SASL off persists the choice without deleting NickServ credentials")
	func saslChoiceDoesNotDeleteCredentials() throws {
		let picker = OnboardingNetworkPickerModel()
		picker.networks.selection = .customServer
		picker.draft.serverAddress = "irc.example.test"
		picker.setAccountName("account")
		picker.draft.accountPassword = "secret"
		picker.draft.usesSASL = false
		let config = try #require(picker.serverConfig())
		#expect(config.usesSASL == false)
		#expect(config.pendingNicknamePassword == .set("secret"))
		#expect(config.username == "account")
		picker.networks.selection = .customServer
		#expect(picker.draft.accountPassword == "secret")
		#expect(picker.draft.accountName == "account")
	}

	/** "Set Up Later" is the one way out that applies nothing.

	 It used to share its behaviour with a Cancel button that committed every
	 setting the person had typed on their way past it. */
	@Test("Set Up Later applies nothing and does not come back")
	func setUpLaterCompletesWithoutApplying() {
		var events: [String] = []
		let model = identifiedModel(
			createConnection: { _, _ in Issue.record("Set Up Later created a connection"); return false },
			applySettings: { _ in Issue.record("Set Up Later saved settings") },
			markCompleted: { events.append("complete") }
		)
		_ = model.advance()

		model.setUpLater()
		model.setUpLater()

		#expect(events == ["complete"])
	}

	@Test("Every appearance the picker offers has a title of its own")
	func appearanceTitlesCoverEveryCase() {
		let titles = PreferredAppearance.allCases.map { String(localized: $0.onboardingTitle) }

		#expect(titles.count == PreferredAppearance.allCases.count)
		#expect(Set(titles).count == titles.count)
		#expect(titles.contains(where: \.isEmpty) == false)
	}

	@Test("Finish without a network saves preferences and completes once")
	func finishesWithoutNetwork() async {
		var events: [String] = []
		let model = identifiedModel(
			createConnection: { _, _ in Issue.record("Unexpected connection"); return false },
			applySettings: { finished in
				#expect(finished.accepted.identity?.nickname == "alice")
				events.append("save")
			},
			markCompleted: { events.append("complete") }
		)
		advance(model, to: .summary)
		#expect(model.advance())
		#expect(events.isEmpty)

		#expect(await model.finish())
		#expect(await model.finish())

		#expect(events == ["save", "complete"])
		#expect(model.isCompleting == false)
	}

	/// A skipped step leaves its settings alone, which is the whole reason a
	/// step records what it accepted rather than what its controls show.
	@Test("Only the steps that were accepted are applied")
	func skippedStepsApplyNothing() async {
		var saves = 0
		let model = identifiedModel(
			createConnection: { _, _ in Issue.record("Unexpected connection"); return false },
			applySettings: { finished in
				#expect(finished.accepted.identity?.nickname == "alice")
				#expect(finished.accepted.appearance == nil)
				#expect(finished.accepted.notifications?.notifyAboutMentions == true)
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

		#expect(await model.finish())
		#expect(saves == 1)
	}

	@Test("Failed session creation remains retryable and never marks completion")
	func failedFinishCanRetry() async {
		let settings = OnboardingSettings()
		settings.identity.nickname = "alice"
		settings.identity.realName = "Alice"
		settings.identity.alternateNickname = "alice_"
		settings.network.connectWhenFinished = false
		var attempts = 0
		var events: [String] = []
		let model = OnboardingModel(
			settings: settings,
			notificationAuthorization: testAuthorization,
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
		model.networkPicker.networks.selection = .customServer
		model.networkPicker.draft.serverAddress = "irc.example.test"
		advance(model, to: .summary)
		#expect(model.advance())

		#expect(await model.finish() == false)
		#expect(model.completionFailure == String(localized: .Onboarding.connectionUnavailable))
		#expect(model.isCompletionFailurePresented)
		#expect(events.isEmpty)

		model.isCompletionFailurePresented = false
		#expect(model.completionFailure == nil)
		#expect(await model.finish())
		#expect(attempts == 2)
		#expect(events == ["save", "complete"])
	}
}
