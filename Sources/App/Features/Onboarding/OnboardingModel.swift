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

	/** Told after the person has answered the permission prompt.

	 Whether the system will play a notification's sound follows from that
	 answer, and the notification controller reads it once at launch. On a first
	 launch the answer arrives here instead, so the controller is asked to read
	 it again — otherwise it spends the rest of the session believing sounds are
	 the application's job and plays them itself. */
	var soundDeliveryDidChange: @MainActor () async -> Void = {
		await SharedApplication.sharedNotificationController().refreshSoundDelivery()
	}

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

	var title: String {
		switch self {
		case .bubbles: OnboardingStrings.Appearance.bubblesTitle
		case .lines: OnboardingStrings.Appearance.linesTitle
		}
	}

	var summary: String {
		switch self {
		case .bubbles: OnboardingStrings.Appearance.bubblesDescription
		case .lines: OnboardingStrings.Appearance.linesDescription
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

	var title: String {
		switch self {
		case .identity: OnboardingStrings.Identity.title
		case .appearance: OnboardingStrings.Appearance.title
		case .notifications: OnboardingStrings.Notifications.title
		case .network: OnboardingStrings.FirstNetwork.title
		case .summary: OnboardingStrings.Summary.title
		}
	}

	var subtitle: String {
		switch self {
		case .identity: OnboardingStrings.Identity.subtitle
		case .appearance: OnboardingStrings.Appearance.subtitle
		case .notifications: OnboardingStrings.Notifications.subtitle
		case .network: OnboardingStrings.FirstNetwork.subtitle
		case .summary: OnboardingStrings.Summary.subtitle
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
	var notificationPermissionMessage = OnboardingStrings.Notifications.permissionExplanation
	var notificationPermissionSymbol = "bell.badge"

	init(
		settings: OnboardingSettings,
		networkPicker: NetworkPickerModel = NetworkPickerModel(),
		notificationAuthorization: OnboardingNotificationAuthorization = .live
	) {
		self.settings = settings
		self.networkPicker = networkPicker
		self.notificationAuthorization = notificationAuthorization
	}

	var isFirstStep: Bool {
		currentStep == .identity
	}

	var isLastStep: Bool {
		currentStep == .summary
	}

	var primaryButtonTitle: String {
		isLastStep ? OnboardingStrings.Window.finishButton : OnboardingStrings.Window.continueButton
	}

	var progressDescription: String {
		OnboardingStrings.Window.progress(
			currentStep: currentStep.rawValue + 1,
			totalSteps: OnboardingStep.allCases.count
		)
	}

	// MARK: - Validation

	/// The complaint to show under the nickname field, or `nil` when it holds a
	/// nickname the server will accept.
	var nicknameProblem: String? {
		let nickname = settings.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
		if nickname.isEmpty {
			return OnboardingStrings.Identity.nicknameRequired
		}
		return ServerPropertiesValidation.isNickname(nickname) ? nil : CommonValidationStrings.invalidNickname
	}

	var alternateNicknameProblem: String? {
		let alternate = settings.alternateNickname.trimmingCharacters(in: .whitespacesAndNewlines)
		guard alternate.isEmpty == false else { return nil }
		return ServerPropertiesValidation.isNickname(alternate) ? nil : CommonValidationStrings.invalidNickname
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
			notificationPermissionMessage = OnboardingStrings.Notifications.permissionGranted
			notificationPermissionSymbol = "bell.badge.fill"
		case .denied:
			notificationPermissionMessage = OnboardingStrings.Notifications.permissionDenied
			notificationPermissionSymbol = "bell.slash"
		default:
			notificationPermissionMessage = OnboardingStrings.Notifications.permissionExplanation
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
				await notificationAuthorization.soundDeliveryDidChange()
			} catch {
				onboardingLogger.error(
					"Notifications failed to authorize: \(error.localizedDescription, privacy: .public)"
				)
			}
		}
	}
}
