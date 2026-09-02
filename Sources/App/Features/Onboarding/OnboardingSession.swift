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

	public static func shouldPresentOnLaunch() -> Bool {
		if Preferences.Identity.onboardingCompleted.value {
			return false
		}

		return (AppController.shared.world?.clientCount ?? 0) == 0
	}

	public init() {
		let settings = OnboardingSettings()
		settings.nickname = Preferences.Identity.nickname.detachedValue
		settings.realName = Preferences.Identity.realName.detachedValue
		settings.textSize = OnboardingSettings.textSize(
			forFontSize: SharedApplication.sharedThemeController().theme.fontSize
		)
		settings.appearance = Preferences.Appearance.preferredAppearance.value

		model = OnboardingModel(settings: settings)
	}

	/// Advances one step and applies the collected settings after the last step.
	/// Returns `true` when the scene should close.
	func continueFlow() -> Bool {
		if model.continueFlow() {
			finish()
			return true
		}
		return false
	}

	func moveBack() {
		model.moveBack()
	}

	func markCompleted() {
		Preferences.Identity.onboardingCompleted.value = true
	}

	private func finish() {
		guard finished == false else { return }
		finished = true

		applyIdentitySettings()
		applyAppearanceSettings()
		applyNotificationSettings()
		createClient()
		markCompleted()
	}

	private func applyIdentitySettings() {
		if model.settings.nickname.isEmpty == false {
			Preferences.Identity.nickname.value = model.settings.nickname
		}

		if model.settings.realName.isEmpty == false {
			Preferences.Identity.realName.value = model.settings.realName
		}
	}

	private func applyAppearanceSettings() {
		var reloadAction: PreferencesReloadAction = []
		let fontSize = OnboardingSettings.fontSize(for: model.settings.textSize)
		var transcriptTheme = model.settings.transcriptStyle.theme
		transcriptTheme.fontSize = fontSize
		SharedApplication.sharedThemeController().apply(transcriptTheme)

		if Preferences.Appearance.preferredAppearance.value != model.settings.appearance {
			Preferences.Appearance.preferredAppearance.value = model.settings.appearance
			reloadAction.insert(.appearance)
		}

		if reloadAction.isEmpty == false {
			TextualPreferences.performReloadAction(reloadAction)
		}
	}

	private func applyNotificationSettings() {
		Preferences.Notifications.flag(.highlight, .enabled).value = model.settings.notifyOnHighlight
		Preferences.Notifications.flag(.privateMessage, .enabled).value = model.settings.notifyOnPrivateMessage
		Preferences.Notifications.flag(.newPrivateMessage, .enabled).value = model.settings.notifyOnPrivateMessage
		Preferences.Notifications.soundIsMuted.value = model.settings.playSounds == false
	}

	private func createClient() {
		guard var config = model.settings.clientConfig else { return }

		config.nickname = model.settings.nickname
		if model.settings.realName.isEmpty == false {
			config.realName = model.settings.realName
		}
		if model.settings.alternateNickname.isEmpty == false {
			config.alternateNicknames = [model.settings.alternateNickname]
		}
		config.autoConnect = model.settings.connectWhenFinished
		config.channelList = model.settings.channelsToJoin.map(ChannelConfig.seed(withName:))

		guard
			let world = AppController.shared.world,
			let mainWindow = AppController.shared.mainWindow
		else {
			onboardingLogger.error("Cannot create a connection before the world is ready")
			return
		}

		let client = world.createClient(with: config)
		mainWindow.expandClient(client)
		world.save()
		_ = mainWindow.reloadLoadingScreen()

		if model.settings.connectWhenFinished {
			client.connect()
		}

		client.selectFirstChannelInChannelList()
	}
}
