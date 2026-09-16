/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation
import os
import UserNotifications

private let onboardingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Onboarding"
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

enum OnboardingTextSize: UInt, CaseIterable, Identifiable {
	case small
	case medium
	case large

	var id: Self {
		self
	}

	var title: LocalizedStringResource {
		switch self {
		case .small: .Onboarding.stepLookAndFeelSmall
		case .medium: .Onboarding.stepLookAndFeelMedium
		case .large: .Onboarding.stepLookAndFeelLarge
		}
	}
}

/// The two transcript appearances the appearance step offers.
enum OnboardingTranscriptStyle: CaseIterable, Identifiable {
	case bubbles
	case lines

	var id: Self {
		self
	}

	var theme: TranscriptTheme {
		switch self {
		case .bubbles: .bubbles
		case .lines: .lines
		}
	}

	var title: LocalizedStringResource {
		switch self {
		case .bubbles: .Onboarding.stepLookAndFeelBubbles
		case .lines: .Onboarding.stepLookAndFeelLines
		}
	}

	var summary: LocalizedStringResource {
		switch self {
		case .bubbles: .Onboarding.messagesInRoundedBubbles
		case .lines: .Onboarding.classicLineByLineView
		}
	}
}

extension PreferredAppearance {
	/// One title per case, so the appearance step's picker cannot drift out of
	/// step with the tags it sets.
	var onboardingTitle: LocalizedStringResource {
		switch self {
		case .inherited: .Onboarding.stepLookAndFeelSystem
		case .light: .Onboarding.stepLookAndFeelLight
		case .dark: .Onboarding.stepLookAndFeelDark
		}
	}
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

@Observable
final class OnboardingSettings {
	var nickname = ""
	var realName = ""
	var alternateNickname = ""

	var transcriptStyle: OnboardingTranscriptStyle = .bubbles
	var textSize: OnboardingTextSize = .medium
	var appearance: PreferredAppearance = .inherited

	var notifyOnHighlight = true
	var notifyOnPrivateMessage = true
	var playSounds = true

	var clientConfig: ClientConfig?
	var connectWhenFinished = true
	var channelsToJoin: [String] = []

	static func fontSize(for textSize: OnboardingTextSize) -> CGFloat {
		switch textSize {
		case .small: 11
		case .medium: 13
		case .large: 15
		}
	}

	static func textSize(forFontSize fontSize: CGFloat) -> OnboardingTextSize {
		if fontSize < 12 {
			return .small
		}
		if fontSize > 14 {
			return .large
		}
		return .medium
	}
}

@MainActor
@Observable
final class OnboardingModel {
	struct Identity: Equatable {
		let nickname: String
		let realName: String
		let alternateNickname: String
	}

	struct Notifications: Equatable {
		let highlight: Bool
		let privateMessage: Bool
		let sounds: Bool
	}

	struct Appearance: Equatable {
		let transcriptStyle: OnboardingTranscriptStyle
		let textSize: OnboardingTextSize
		let preferredAppearance: PreferredAppearance

		var theme: TranscriptTheme {
			var theme = transcriptStyle.theme
			theme.fontSize = OnboardingSettings.fontSize(for: textSize)
			return theme
		}
	}

	let settings: OnboardingSettings
	let networkPicker: NetworkPickerModel
	private let notificationAuthorization: OnboardingNotificationAuthorization
	private var authorizationTask: Task<Void, Never>?

	/** What each step contributed, rather than what its controls currently show.

	 A step contributes only once it has been accepted with Continue: passing
	 over a step with Skip, or leaving onboarding without reaching it, has to
	 leave the corresponding preferences exactly as they were. */
	private(set) var acceptedIdentity: Identity?
	private(set) var acceptedAppearance: Appearance?
	private(set) var acceptedNotifications: Notifications?

	var currentStep: OnboardingStep = .identity
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
	private let createConnection: @MainActor (ClientConfig, Bool) -> Bool
	private let applySettings: @MainActor (OnboardingModel) -> Void
	private let markCompleted: @MainActor () -> Void

	static func shouldPresentOnLaunch() -> Bool {
		if Preferences.Identity.onboardingCompleted.value {
			return false
		}

		return (AppServices.clientDirectory?.clientCount ?? 0) == 0
	}

	/// Seeded from the preferences the flow writes back to, so the first step
	/// already shows whatever the person has set elsewhere.
	convenience init() {
		let settings = OnboardingSettings()
		settings.nickname = Preferences.Identity.nickname.detachedValue
		settings.realName = Preferences.Identity.realName.detachedValue
		settings.textSize = OnboardingSettings.textSize(
			forFontSize: AppServices.theme.theme.fontSize
		)
		settings.appearance = Preferences.Appearance.preferredAppearance.value

		self.init(settings: settings)
	}

	/// Everything the flow reaches outside itself is passed in, so a test can
	/// drive the whole thing without a world, preferences or a window.
	init(
		settings: OnboardingSettings,
		networkPicker: NetworkPickerModel = NetworkPickerModel(),
		notificationAuthorization: OnboardingNotificationAuthorization = .live,
		createConnection: (@MainActor (ClientConfig, Bool) -> Bool)? = nil,
		applySettings: (@MainActor (OnboardingModel) -> Void)? = nil,
		markCompleted: (@MainActor () -> Void)? = nil
	) {
		self.settings = settings
		self.networkPicker = networkPicker
		self.notificationAuthorization = notificationAuthorization
		self.createConnection = createConnection ?? Self.createClient
		self.applySettings = applySettings ?? Self.applyAcceptedSettings
		self.markCompleted = markCompleted ?? { Preferences.Identity.onboardingCompleted.value = true }
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
		let nickname = settings.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
		if nickname.isEmpty {
			return String(localized: .Onboarding.stepWelcomeAndIdentityNicknameRequired)
		}
		return (nickname as NSString).isHostmaskNickname ? nil : CommonValidationStrings.invalidNickname
	}

	var alternateNicknameProblem: String? {
		let alternate = settings.alternateNickname.trimmingCharacters(in: .whitespacesAndNewlines)
		guard alternate.isEmpty == false else { return nil }
		return (alternate as NSString).isHostmaskNickname ? nil : CommonValidationStrings.invalidNickname
	}

	/// The same rule the server properties sheet applies, so a real name
	/// accepted here is not refused the first time that sheet is saved.
	var realNameProblem: String? {
		ServerPropertiesValidation.isRealName(settings.realName) ? nil : CommonValidationStrings.invalidRealName
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
		case .appearance:
			acceptedAppearance = nil
		case .notifications:
			acceptedNotifications = nil
		case .network:
			settings.clientConfig = nil
			settings.channelsToJoin = []
		case .identity, .summary:
			break
		}

		currentStep = next
		prepareCurrentStep()
	}

	private func prepareCurrentStep() {
		/* The notifications step reads the permission from its own view task,
		 which starts when the step appears and stops when it goes. Starting a
		 second read here asked the system twice for every visit. */
		if currentStep == .network {
			networkPicker.updateDefaultNickname(settings.nickname)
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

	private func acceptCurrentStep() {
		switch currentStep {
		case .identity:
			acceptIdentity()
		case .appearance:
			acceptedAppearance = Appearance(
				transcriptStyle: settings.transcriptStyle,
				textSize: settings.textSize,
				preferredAppearance: settings.appearance
			)
		case .notifications:
			acceptedNotifications = Notifications(
				highlight: settings.notifyOnHighlight,
				privateMessage: settings.notifyOnPrivateMessage,
				sounds: settings.playSounds
			)
			requestNotificationAuthorization()
		case .network:
			acceptNetwork()
		case .summary:
			break
		}
	}

	private func acceptIdentity() {
		settings.nickname = settings.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
		settings.realName = settings.realName.trimmingCharacters(in: .whitespacesAndNewlines)
		settings.alternateNickname = settings.alternateNickname
			.trimmingCharacters(in: .whitespacesAndNewlines)
		acceptedIdentity = Identity(
			nickname: settings.nickname,
			realName: settings.realName,
			alternateNickname: settings.alternateNickname
		)
	}

	private func acceptNetwork() {
		guard networkPicker.hasSelection else {
			settings.clientConfig = nil
			settings.channelsToJoin = []
			return
		}

		settings.clientConfig = networkPicker.clientConfig()
		settings.channelsToJoin = networkPicker.suggestedChannels.filter {
			networkPicker.selectedChannels.contains($0)
		}
	}

	private func requestNotificationAuthorization() {
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

		if let config = configuredClient() {
			guard createConnection(config, settings.connectWhenFinished) else {
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

	private func configuredClient() -> ClientConfig? {
		guard let identity = acceptedIdentity, var config = settings.clientConfig else {
			return nil
		}

		config.nickname = identity.nickname
		config.realName = identity.realName
		config.alternateNicknames = identity.alternateNickname.isEmpty ? [] : [identity.alternateNickname]
		config.autoConnect = settings.connectWhenFinished
		config.channelList = settings.channelsToJoin.map(ChannelConfig.seed(withName:))
		return config
	}

	private static func applyAcceptedSettings(_ model: OnboardingModel) {
		if let identity = model.acceptedIdentity {
			Preferences.Identity.nickname.value = identity.nickname
			Preferences.Identity.realName.value = identity.realName
		}
		if let appearance = model.acceptedAppearance {
			AppServices.theme.apply(appearance.theme)
			if Preferences.Appearance.preferredAppearance.value != appearance.preferredAppearance {
				Preferences.Appearance.preferredAppearance.value = appearance.preferredAppearance
				PreferenceReload.perform(.appearance)
			}
		}
		if let notifications = model.acceptedNotifications {
			Preferences.Notifications.notifyAboutMentions.value = notifications.highlight || notifications.privateMessage
			Preferences.Notifications.soundIsMuted.value = notifications.sounds == false
		}
	}

	private static func createClient(_ config: ClientConfig, connectWhenFinished: Bool) -> Bool {
		guard
			let world = AppServices.clientDirectory,
			let mainWindow = AppServices.delegate.mainWindow
		else {
			onboardingLogger.error("Cannot create a connection before the world is ready")
			return false
		}

		let client = world.createClient(with: config)
		mainWindow.expandClient(client)
		world.save()
		_ = mainWindow.reloadLoadingScreen()

		if connectWhenFinished {
			client.connect()
		}

		client.selectFirstChannelInChannelList()
		return true
	}
}
