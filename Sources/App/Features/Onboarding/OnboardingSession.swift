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

private let onboardingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Onboarding"
)

@MainActor
@Observable
public final class OnboardingSession {
	let model: OnboardingModel
	private var finished = false
	private let createConnection: (ClientConfig, Bool) -> Bool
	private let applySettings: (OnboardingModel) -> Void
	private let markCompleted: () -> Void

	public static func shouldPresentOnLaunch() -> Bool {
		if Preferences.Identity.onboardingCompleted.value {
			return false
		}

		return (AppController.shared.world?.clientCount ?? 0) == 0
	}

	public convenience init() {
		let settings = OnboardingSettings()
		settings.nickname = Preferences.Identity.nickname.detachedValue
		settings.realName = Preferences.Identity.realName.detachedValue
		settings.textSize = OnboardingSettings.textSize(
			forFontSize: SharedApplication.sharedThemeController().theme.fontSize
		)
		settings.appearance = Preferences.Appearance.preferredAppearance.value

		self.init(
			model: OnboardingModel(settings: settings),
			createConnection: Self.createClient,
			applySettings: Self.applyAcceptedSettings,
			markCompleted: { Preferences.Identity.onboardingCompleted.value = true }
		)
	}

	init(
		model: OnboardingModel,
		createConnection: @escaping (ClientConfig, Bool) -> Bool,
		applySettings: @escaping (OnboardingModel) -> Void,
		markCompleted: @escaping () -> Void
	) {
		self.model = model
		self.createConnection = createConnection
		self.applySettings = applySettings
		self.markCompleted = markCompleted
	}

	/// Advances one step and applies the collected settings after the last step.
	/// Returns `true` when the scene should close.
	func continueFlow() -> Bool {
		guard finished == false else { return true }
		if model.continueFlow() {
			return finish()
		}
		return false
	}

	func moveBack() {
		model.moveBack()
	}

	func skipRemainingSteps() -> Bool {
		guard finished == false else { return true }
		guard model.skipRemainingSteps() else { return false }
		return finish()
	}

	/** The title-bar close button.

	 Closing the window is the same decision as pressing Cancel — the user is
	 done with onboarding — so it persists what Cancel persists. Treating it as
	 "nothing happened" is what made onboarding come back at every launch after
	 the user had closed it. */
	func windowDidClose() {
		_ = cancel()
	}

	/** Cancel retains previously accepted steps, not an unfinished network draft.

	 Closing onboarding is an answer, so it is recorded even when no step was
	 ever accepted. Returning early on an unaccepted identity left the window
	 re-presenting itself at every launch, with no way to stop it. */
	func cancel() -> Bool {
		guard finished == false else { return true }

		guard model.acceptedIdentity != nil else {
			return dismissWithoutSetup()
		}

		model.settings.clientConfig = nil
		model.settings.channelsToJoin = []
		return finish()
	}

	/// "Set Up Later": nothing is applied, and onboarding does not come back.
	func setUpLater() -> Bool {
		guard finished == false else { return true }

		return dismissWithoutSetup()
	}

	private func dismissWithoutSetup() -> Bool {
		markCompleted()
		finished = true
		return true
	}

	private func finish() -> Bool {
		guard finished == false else { return true }
		guard let identity = model.acceptedIdentity else { return false }
		if var config = model.settings.clientConfig {
			config.nickname = identity.nickname
			config.realName = identity.realName
			config.alternateNicknames = identity.alternateNickname.isEmpty ? [] : [identity.alternateNickname]
			config.autoConnect = model.settings.connectWhenFinished
			config.channelList = model.settings.channelsToJoin.map(ChannelConfig.seed(withName:))
			guard createConnection(config, model.settings.connectWhenFinished) else {
				model.validationMessage = OnboardingStrings.Window.connectionUnavailable
				model.isValidationPresented = true
				return false
			}
		}
		applySettings(model)
		markCompleted()
		finished = true
		return true
	}

	private static func applyAcceptedSettings(_ model: OnboardingModel) {
		if let identity = model.acceptedIdentity {
			Preferences.Identity.nickname.value = identity.nickname
			Preferences.Identity.realName.value = identity.realName
		}
		if let appearance = model.acceptedAppearance {
			SharedApplication.sharedThemeController().apply(appearance.theme)
			if Preferences.Appearance.preferredAppearance.value != appearance.appearance {
				Preferences.Appearance.preferredAppearance.value = appearance.appearance
				TextualPreferences.performReloadAction(.appearance)
			}
		}
		if let notifications = model.acceptedNotifications {
			Preferences.Notifications.flag(.highlight, .enabled).value = notifications.highlight
			Preferences.Notifications.flag(.privateMessage, .enabled).value = notifications.privateMessage
			Preferences.Notifications.flag(.newPrivateMessage, .enabled).value = notifications.privateMessage
			Preferences.Notifications.soundIsMuted.value = notifications.sounds == false
		}
	}

	private static func createClient(_ config: ClientConfig, connectWhenFinished: Bool) -> Bool {
		guard
			let world = AppController.shared.world,
			let mainWindow = AppController.shared.mainWindow
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
