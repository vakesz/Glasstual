// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import os
import UserNotifications

private let onboardingLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "OnboardingModel"
)

struct OnboardingNotificationAuthorization {
	let currentStatus: () async -> UNAuthorizationStatus
	let request: () async throws -> Bool

	static let live = OnboardingNotificationAuthorization(
		currentStatus: {
			await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
		},
		request: {
			try await UNUserNotificationCenter.current().requestAuthorization(
				options: [.alert, .sound, .providesAppNotificationSettings]
			)
		}
	)
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
	case identity
	case appearance
	case notifications
	case network
	case summary

	var id: Self {
		self
	}

	var title: LocalizedStringResource {
		switch self {
		case .identity: .Onboarding.welcomeToGlasstual
		case .appearance: .Onboarding.lookAndFeel
		case .notifications: .Onboarding.stepNotifications
		case .network: .Onboarding.yourFirstNetwork
		case .summary: .Onboarding.summary
		}
	}

	var subtitle: LocalizedStringResource {
		switch self {
		case .identity: .Onboarding.glasstualIsAnIrcClientBuilt
		case .appearance: .Onboarding.chooseHowConversationsAreDisplayed
		case .notifications: .Onboarding.chooseWhatGlasstualShouldTell
		case .network: .Onboarding.pickANetworkToJoin
		case .summary: .Onboarding.summaryReviewYourChoices
		}
	}

	/// Identity is what every later step is written into, and the summary is
	/// the review of what was chosen, so neither can be passed over.
	var isSkippable: Bool {
		self != .identity && self != .summary
	}
}

@MainActor
@Observable
final class OnboardingModel {
	let settings: OnboardingSettings
	let networkPicker: OnboardingNetworkPickerModel
	private let notificationAuthorization: OnboardingNotificationAuthorization
	private var authorizationTask: Task<Void, Never>?

	/// What the accepted steps chose. Everything onboarding applies on the way
	/// out is read from here and nowhere else.
	private(set) var accepted = OnboardingAcceptedSteps()

	var currentStep: OnboardingStep = .identity {
		didSet { movesForward = currentStep.rawValue >= oldValue.rawValue }
	}

	private(set) var movesForward = true
	var notificationPermissionMessage: LocalizedStringResource = .Onboarding.glasstualWillAskMacosForPermission
	var notificationPermissionSymbol = "bell.badge"

	/// Shown on the summary step while the choices are being applied and the
	/// first connection created, so Finish is not a window that just vanishes.
	private(set) var isCompleting = false

	/// The one failure onboarding cannot show beside a field: the application
	/// was not ready to create the connection. Presented as an alert, and
	/// cleared when the person dismisses it so Finish can be tried again.
	var completionFailure: String?

	/// Drives the alert the failure is shown in; dismissing it clears the
	/// failure so Finish can be pressed again.
	var isCompletionFailurePresented: Bool {
		get { completionFailure != nil }
		set {
			if newValue == false {
				completionFailure = nil
			}
		}
	}

	private var finished = false
	private let createConnection: @MainActor (ServerConfig, Bool) -> Bool
	private let applySettings: @MainActor (OnboardingModel) -> Void
	private let markCompleted: @MainActor () -> Void

	static func shouldPresentOnLaunch() -> Bool {
		if SettingsKeys.Identity.onboardingCompleted.value {
			return false
		}

		return (AppServices.chatSession?.sessionCount ?? 0) == 0
	}

	/// Seeded from the settings the flow writes back to, so the first step
	/// already shows whatever the person has set elsewhere.
	convenience init() {
		let settings = OnboardingSettings()
		settings.identity.nickname = SettingsKeys.Identity.nickname.detachedValue
		settings.identity.realName = SettingsKeys.Identity.realName.detachedValue
		settings.appearance.textSize = OnboardingTextSize(fontSize: AppServices.theme.theme.fontSize)
		settings.appearance.preferredAppearance = SettingsKeys.Appearance.preferredAppearance.value

		self.init(settings: settings)
	}

	/// Everything the flow reaches outside itself is passed in, so a test can
	/// drive the whole thing without a chat session, settings or a window.
	init(
		settings: OnboardingSettings,
		networkPicker: OnboardingNetworkPickerModel = OnboardingNetworkPickerModel(),
		notificationAuthorization: OnboardingNotificationAuthorization = .live,
		createConnection: (@MainActor (ServerConfig, Bool) -> Bool)? = nil,
		applySettings: (@MainActor (OnboardingModel) -> Void)? = nil,
		markCompleted: (@MainActor () -> Void)? = nil
	) {
		self.settings = settings
		self.networkPicker = networkPicker
		self.notificationAuthorization = notificationAuthorization
		self.createConnection = createConnection ?? Self.createSession
		self.applySettings = applySettings ?? Self.applyAcceptedSettings
		self.markCompleted = markCompleted ?? { SettingsKeys.Identity.onboardingCompleted.value = true }
	}

	var isFirstStep: Bool {
		currentStep == .identity
	}

	var isLastStep: Bool {
		currentStep == .summary
	}

	var primaryButtonTitle: LocalizedStringResource {
		isLastStep ? .Onboarding.windowChromeFinish : .Onboarding.windowChromeContinue
	}

	var progressDescription: LocalizedStringResource {
		.Onboarding.windowChromeStep(currentStep.rawValue + 1, OnboardingStep.allCases.count)
	}

	// MARK: - Validation

	/// The complaint to show under the nickname field, or `nil` when it holds a
	/// nickname the server will accept.
	var nicknameProblem: String? {
		let nickname = settings.identity.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
		if nickname.isEmpty {
			return String(localized: .Onboarding.stepWelcomeAndIdentityNicknameRequired)
		}
		return nickname.isHostmaskNickname ? nil : CommonValidationStrings.invalidNickname
	}

	var alternateNicknameProblem: String? {
		let alternate = settings.identity.alternateNickname.trimmingCharacters(in: .whitespacesAndNewlines)
		guard alternate.isEmpty == false else { return nil }
		return alternate.isHostmaskNickname ? nil : CommonValidationStrings.invalidNickname
	}

	/// The same rule the server properties sheet applies, so a real name
	/// accepted here is not refused the first time that sheet is saved.
	var realNameProblem: String? {
		ServerPropertiesValidation.isRealName(settings.identity.realName)
			? nil
			: CommonValidationStrings.invalidRealName
	}

	/// Drives the primary button. Nothing is rejected after the fact, so every
	/// step either shows what is wrong beside the field or lets Continue work.
	var isCurrentStepValid: Bool {
		switch currentStep {
		case .identity:
			nicknameProblem == nil && alternateNicknameProblem == nil && realNameProblem == nil
		case .network:
			networkPicker.isValid
		case .appearance, .notifications, .summary:
			true
		}
	}

	// MARK: - Navigation

	func moveBack() {
		guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
		currentStep = previous
		prepareCurrentStep()
	}

	/// Accepts the current step. Returns `true` when the last step was accepted
	/// and the collected settings are ready to be applied.
	func advance() -> Bool {
		guard isCurrentStepValid else { return false }

		acceptCurrentStep()

		guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
			return true
		}

		currentStep = next
		prepareCurrentStep()
		return false
	}

	/// Moves past the current step without accepting it, and drops anything an
	/// earlier visit to it had accepted.
	func skip() {
		guard currentStep.isSkippable, let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
			return
		}

		switch currentStep {
		case .appearance: accepted.appearance = nil
		case .notifications: accepted.notifications = nil
		case .network: accepted.network = nil
		case .identity, .summary: break
		}

		currentStep = next
		prepareCurrentStep()
	}

	private func prepareCurrentStep() {
		/* The notifications step reads the permission from its own view task,
		 which starts when the step appears and stops when it goes. Starting a
		 second read here asked the system twice for every visit. */
		if currentStep == .network {
			networkPicker.updateDefaultNickname(settings.identity.nickname)
		}
	}

	/// Waits for the permission prompt the notifications step raised, so the
	/// window cannot close out from under a dialog the system is still showing.
	func completePendingWork() async {
		await authorizationTask?.value
	}

	func refreshNotificationPermission() async {
		let authorizationStatus = await notificationAuthorization.currentStatus()

		switch authorizationStatus {
		case .authorized, .provisional:
			notificationPermissionMessage = .Onboarding.notificationsAreAllowedForGlasstual
			notificationPermissionSymbol = "bell.badge.fill"
		case .denied:
			notificationPermissionMessage = .Onboarding.notificationsAreTurnedOffForGlasstual
			notificationPermissionSymbol = "bell.slash"
		default:
			notificationPermissionMessage = .Onboarding.glasstualWillAskMacosForPermission
			notificationPermissionSymbol = "bell.badge"
		}
	}

	// MARK: - Accepting a step

	/// A step is accepted by handing over the value it was editing; the network
	/// step adds what its picker answered, which is not on screen anywhere.
	private func acceptCurrentStep() {
		switch currentStep {
		case .identity:
			settings.identity.trimWhitespace()
			accepted.identity = settings.identity
		case .appearance:
			accepted.appearance = settings.appearance
		case .notifications:
			accepted.notifications = settings.notifications
			requestNotificationAuthorization()
		case .network:
			settings.network.serverConfig = networkPicker.serverConfig()
			settings.network.channelsToJoin = networkPicker.channelsToJoin
			accepted.network = settings.network
		case .summary:
			break
		}
	}

	private func requestNotificationAuthorization() {
		guard settings.notifications.notifyAboutMentions else { return }

		authorizationTask = Task {
			do {
				_ = try await notificationAuthorization.request()
				await refreshNotificationPermission()
			} catch {
				onboardingLogger.error(
					"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
				)
			}
		}
	}

	// MARK: - Leaving onboarding

	/** Applies what the accepted steps chose and creates the first connection.

	 Returns `true` when the window should close. A connection that could not be
	 created leaves onboarding open and unmarked, so Finish can be pressed
	 again once the application has finished starting up. */
	func finish() async -> Bool {
		guard finished == false else { return true }

		isCompleting = true
		defer { isCompleting = false }

		/* The notifications step raises the system permission prompt in a task
		 of its own; closing the window while it is still up would leave the
		 answer landing on a dismissed scene. */
		await completePendingWork()

		/* The title-bar close button still works while this runs, and closing
		 the window is a dismissal that answers onboarding on its own. */
		guard finished == false else { return true }

		if let connection = acceptedConnection {
			guard createConnection(connection.config, connection.connectWhenFinished) else {
				completionFailure = String(localized: .Onboarding.connectionUnavailable)
				return false
			}
		}

		applySettings(self)
		markCompleted()
		finished = true
		return true
	}

	/** "Set Up Later", Escape, and the title-bar close button.

	 Nothing the person typed is applied, but the fact that they answered is
	 recorded: leaving onboarding unmarked is what made the window re-present
	 itself at every launch with no way to stop it. */
	func setUpLater() {
		guard finished == false else { return }

		markCompleted()
		finished = true
	}

	/// The connection the accepted steps describe, and whether to connect it at
	/// once. `nil` when no network was chosen, which is a supported answer.
	private var acceptedConnection: (config: ServerConfig, connectWhenFinished: Bool)? {
		guard let identity = accepted.identity,
		      let network = accepted.network,
		      var config = network.serverConfig
		else {
			return nil
		}

		config.nickname = identity.nickname
		config.realName = identity.realName
		config.alternateNicknames = identity.alternateNickname.isEmpty ? [] : [identity.alternateNickname]
		config.autoConnect = network.connectWhenFinished
		config.conversationList = network.channelsToJoin.map(ConversationConfig.seed(withName:))

		return (config, network.connectWhenFinished)
	}

	private static func applyAcceptedSettings(_ model: OnboardingModel) {
		if let identity = model.accepted.identity {
			SettingsKeys.Identity.nickname.value = identity.nickname
			SettingsKeys.Identity.realName.value = identity.realName
		}
		if let appearance = model.accepted.appearance {
			AppServices.theme.apply(appearance.theme)
			if SettingsKeys.Appearance.preferredAppearance.value != appearance.preferredAppearance {
				SettingsKeys.Appearance.preferredAppearance.value = appearance.preferredAppearance
				SettingsReload.perform(.appearance)
			}
		}
		if let notifications = model.accepted.notifications {
			SettingsKeys.Notifications.notifyAboutMentions.value = notifications.notifyAboutMentions
			SettingsKeys.Notifications.soundIsMuted.value = notifications.playSounds == false
		}
	}

	private static func createSession(_ config: ServerConfig, connectWhenFinished: Bool) -> Bool {
		guard
			let chatSession = AppServices.chatSession,
			let mainWindow = AppServices.delegate.mainWindow
		else {
			onboardingLogger.error("Cannot create a connection before the chat session is ready")
			return false
		}

		let session = chatSession.createSession(with: config)
		mainWindow.expandSession(session)
		chatSession.save()
		_ = mainWindow.reloadLoadingScreen()

		if connectWhenFinished {
			session.connect()
		}

		session.selectFirstConversation()
		return true
	}
}
