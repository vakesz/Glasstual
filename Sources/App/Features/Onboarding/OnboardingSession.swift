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
final class OnboardingSession {
	let model: OnboardingModel

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
	private let createConnection: (ClientConfig, Bool) -> Bool
	private let applySettings: (OnboardingModel) -> Void
	private let markCompleted: () -> Void

	static func shouldPresentOnLaunch() -> Bool {
		if Preferences.Identity.onboardingCompleted.value {
			return false
		}

		return (AppServices.world?.clientCount ?? 0) == 0
	}

	convenience init() {
		let settings = OnboardingSettings()
		settings.nickname = Preferences.Identity.nickname.detachedValue
		settings.realName = Preferences.Identity.realName.detachedValue
		settings.textSize = OnboardingSettings.textSize(
			forFontSize: AppServices.theme.theme.fontSize
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
		await model.completePendingWork()

		/* The title-bar close button still works while this runs, and closing
		 the window is a dismissal that answers onboarding on its own. */
		guard finished == false else { return true }

		if let config = configuredClient() {
			guard createConnection(config, model.settings.connectWhenFinished) else {
				completionFailure = OnboardingStrings.Window.connectionUnavailable
				return false
			}
		}

		applySettings(model)
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
		guard let identity = model.acceptedIdentity, var config = model.settings.clientConfig else {
			return nil
		}

		config.nickname = identity.nickname
		config.realName = identity.realName
		config.alternateNicknames = identity.alternateNickname.isEmpty ? [] : [identity.alternateNickname]
		config.autoConnect = model.settings.connectWhenFinished
		config.channelList = model.settings.channelsToJoin.map(ChannelConfig.seed(withName:))
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
			let world = AppServices.world,
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
