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

import AppKit
import os
import SwiftUI

private let onboardingWindowLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Onboarding"
)

@MainActor
public protocol OnboardingWindowControllerDelegate: AnyObject {
	func onboardingWindowControllerWillClose(_ sender: OnboardingWindowController)
}

@MainActor
public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
	public weak var delegate: (any OnboardingWindowControllerDelegate)?

	private let model: OnboardingModel
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
		super.init(window: nil)
		installWindow()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func installWindow() {
		let rootView = OnboardingView(
			model: model,
			continueAction: { [weak self] in self?.continueFlow() },
			backAction: { [weak self] in self?.model.moveBack() },
			skipAction: { [weak self] in self?.closeAsCompleted() }
		)
		let onboardingWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
			styleMask: [.titled, .closable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		onboardingWindow.contentViewController = NSHostingController(rootView: rootView)
		onboardingWindow.delegate = self
		onboardingWindow.title = OnboardingStrings.Window.title
		onboardingWindow.titlebarAppearsTransparent = true
		onboardingWindow.titleVisibility = .hidden
		onboardingWindow.isReleasedWhenClosed = false
		onboardingWindow.isRestorable = false
		onboardingWindow.tabbingMode = .disallowed
		onboardingWindow.preventsApplicationTerminationWhenModal = false
		onboardingWindow.autorecalculatesKeyViewLoop = true
		window = onboardingWindow
	}

	public func show() {
		window?.center()
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
	}

	private func continueFlow() {
		window?.makeFirstResponder(nil)

		if model.continueFlow() {
			finish()
		}
	}

	@objc public func cancel(_: Any?) {
		closeAsCompleted()
	}

	override public func cancelOperation(_: Any?) {
		closeAsCompleted()
	}

	private func closeAsCompleted() {
		Preferences.Identity.onboardingCompleted.value = true
		close()
	}

	private func finish() {
		guard finished == false else { return }
		finished = true

		applyIdentitySettings()
		applyAppearanceSettings()
		applyNotificationSettings()
		createClient()
		closeAsCompleted()
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
		var transcriptTheme = model.settings.styleName == "Lines" ? TranscriptTheme.lines : .bubbles
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
			onboardingWindowLogger.error("Cannot create a connection before the world is ready")
			return
		}

		let client = world.createClient(with: config, reload: true)
		mainWindow.expandClient(client)
		world.save()
		_ = mainWindow.reloadLoadingScreen()

		if model.settings.connectWhenFinished {
			client.connect()
		}

		client.selectFirstChannelInChannelList()
	}

	public func windowShouldClose(_: NSWindow) -> Bool {
		Preferences.Identity.onboardingCompleted.value = true
		return true
	}

	public func windowWillClose(_: Notification) {
		delegate?.onboardingWindowControllerWillClose(self)
	}
}
