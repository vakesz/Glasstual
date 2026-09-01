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

	static let live = OnboardingNotificationAuthorization(
		currentStatus: {
			await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
		},
		request: {
			try await UNUserNotificationCenter.current().requestAuthorization(
				options: [.alert, .providesAppNotificationSettings]
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

enum OnboardingStep: Int, CaseIterable, Identifiable {
	case identity
	case appearance
	case notifications
	case network

	var id: Self {
		self
	}

	var title: String {
		switch self {
		case .identity: OnboardingStrings.Identity.title
		case .appearance: OnboardingStrings.Appearance.title
		case .notifications: OnboardingStrings.Notifications.title
		case .network: OnboardingStrings.FirstNetwork.title
		}
	}

	var subtitle: String {
		switch self {
		case .identity: OnboardingStrings.Identity.subtitle
		case .appearance: OnboardingStrings.Appearance.subtitle
		case .notifications: OnboardingStrings.Notifications.subtitle
		case .network: OnboardingStrings.FirstNetwork.subtitle
		}
	}

	var isSkippable: Bool {
		self != .identity
	}
}

@Observable
final class OnboardingSettings {
	var nickname = ""
	var realName = ""
	var alternateNickname = ""

	var styleName = "Bubbles"
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
	let settings: OnboardingSettings
	let networkPicker: NetworkPickerModel
	private let notificationAuthorization: OnboardingNotificationAuthorization

	var currentStep: OnboardingStep = .identity
	var validationMessage = ""
	var isValidationPresented = false
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
		currentStep == .network
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

	func moveBack() {
		guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
		currentStep = previous
		prepareCurrentStep()
	}

	/// Returns `true` when the final step committed successfully.
	func continueFlow() -> Bool {
		do {
			try commitCurrentStep()
		} catch {
			validationMessage = (error as? OnboardingStepError)?.message ?? error.localizedDescription
			isValidationPresented = validationMessage.isEmpty == false
			return false
		}

		guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
			return true
		}

		currentStep = next
		prepareCurrentStep()
		return false
	}

	func prepareCurrentStep() {
		switch currentStep {
		case .notifications:
			Task { await refreshNotificationPermission() }
		case .network:
			networkPicker.updateDefaultNickname(settings.nickname)
		default:
			break
		}
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

	private func commitCurrentStep() throws {
		switch currentStep {
		case .identity:
			try commitIdentity()
		case .appearance:
			break
		case .notifications:
			requestNotificationAuthorization()
		case .network:
			try commitNetwork()
		}
	}

	private func commitIdentity() throws {
		let nickname = settings.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
		let alternate = settings.alternateNickname.trimmingCharacters(in: .whitespacesAndNewlines)

		guard nickname.isEmpty == false else {
			throw OnboardingStepError(ApplicationStrings.requiredField)
		}
		guard ServerPropertiesValidation.isNickname(nickname) else {
			throw OnboardingStepError(CommonValidationStrings.invalidNickname)
		}
		guard alternate.isEmpty || ServerPropertiesValidation.isNickname(alternate) else {
			throw OnboardingStepError(CommonValidationStrings.invalidNickname)
		}

		settings.nickname = nickname
		settings.realName = settings.realName.trimmingCharacters(in: .whitespacesAndNewlines)
		settings.alternateNickname = alternate
	}

	private func requestNotificationAuthorization() {
		Task {
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

	private func commitNetwork() throws {
		guard networkPicker.hasSelection else {
			settings.clientConfig = nil
			settings.channelsToJoin = []
			return
		}

		try networkPicker.validate()
		settings.clientConfig = networkPicker.clientConfig()
		settings.channelsToJoin = networkPicker.suggestedChannels.filter {
			networkPicker.selectedChannels.contains($0)
		}
	}
}

struct OnboardingStepError: Error {
	let message: String

	init(_ message: String) {
		self.message = message
	}
}
