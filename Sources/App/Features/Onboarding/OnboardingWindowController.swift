/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import os
import QuartzCore

private let onboardingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Onboarding"
)

// MARK: - Page Indicator

/** A row of dots; the current page is drawn in the accent colour. */
private final class OnboardingPageIndicatorView: NSView {
	var numberOfPages: Int = 0 {
		didSet {
			needsDisplay = true
		}
	}

	var currentPage: Int = 0 {
		didSet {
			needsDisplay = true
		}
	}

	override func draw(_: NSRect) {
		let count = numberOfPages

		if count == 0 {
			return
		}

		let diameter: CGFloat = 7.0
		let spacing: CGFloat = 9.0
		let totalWidth = (diameter * CGFloat(count)) + (spacing * CGFloat(count - 1))

		var x = bounds.midX - (totalWidth / 2.0)
		let y = bounds.midY - (diameter / 2.0)

		for i in 0 ..< count {
			let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter))

			if i == currentPage {
				NSColor.controlAccentColor.setFill()
			} else {
				NSColor.quaternaryLabelColor.setFill()
			}

			dot.fill()

			x += diameter + spacing
		}
	}

	override func isAccessibilityElement() -> Bool {
		true
	}

	override func accessibilityRole() -> NSAccessibility.Role? {
		.progressIndicator
	}

	override func accessibilityLabel() -> String? {
		OnboardingStrings.Window.progress(currentStep: currentPage + 1, totalSteps: numberOfPages)
	}
}

// MARK: - Window Controller

/// What `OnboardingWindowController` reports back.
@MainActor
public protocol OnboardingWindowControllerDelegate: AnyObject {
	func onboardingWindowControllerWillClose(_ sender: OnboardingWindowController)
}

@objc(TDCOnboardingWindowController)
@MainActor
public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
	public weak var delegate: (any OnboardingWindowControllerDelegate)?

	@IBOutlet private var iconImageView: NSImageView!
	@IBOutlet private var titleTextField: NSTextField!
	@IBOutlet private var subtitleTextField: NSTextField!
	@IBOutlet private var contentContainerView: NSView!
	@IBOutlet private var pageIndicatorView: NSView!
	@IBOutlet private var skipButton: NSButton!
	@IBOutlet private var backButton: NSButton!
	@IBOutlet private var continueButton: NSButton!

	private var pageIndicator: OnboardingPageIndicatorView!
	private var settings: OnboardingSettings!
	private var steps: [OnboardingStepViewController] = []
	private var currentStepIndex: Int = 0
	private var finished = false
	private var transitioning = false

	override public var windowNibName: NSNib.Name? {
		"TDCOnboardingWindow"
	}

	@objc public static func shouldPresentOnLaunch() -> Bool {
		if TextualPreferences.onboardingCompleted() {
			return false
		}

		return (AppController.shared.world?.clientCount ?? 0) == 0
	}

	@objc public init() {
		super.init(window: nil)
		prepareInitialState()
	}

	@available(*, unavailable)
	public required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func prepareInitialState() {
		let settings = OnboardingSettings()
		settings.textSize = OnboardingSettings.textSize(forFontSize: TextualPreferences.themeChannelViewFontSize())
		settings.appearance = TextualPreferences.appearance()

		self.settings = settings

		steps = [
			OnboardingIdentityStepViewController(settings: settings),
			OnboardingAppearanceStepViewController(settings: settings),
			OnboardingNotificationsStepViewController(settings: settings),
			OnboardingNetworkStepViewController(settings: settings),
		]
	}

	override public func windowDidLoad() {
		super.windowDidLoad()

		guard let window else {
			return
		}

		window.title = OnboardingStrings.Window.title
		window.styleMask.insert(.fullSizeContentView)
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden

		iconImageView.image = NSApp.applicationIconImage

		subtitleTextField.maximumNumberOfLines = 2
		subtitleTextField.preferredMaxLayoutWidth = 560

		skipButton.title = OnboardingStrings.Window.skipButton
		backButton.title = OnboardingStrings.Window.backButton

		/* The skip control reads as a link, not a push button, so that the
		 primary action stays the only prominent button on the page. */
		skipButton.isBordered = false
		skipButton.contentTintColor = .linkColor

		let pageIndicator = OnboardingPageIndicatorView(frame: pageIndicatorView.bounds)
		pageIndicator.autoresizingMask = [.width, .height]
		pageIndicator.numberOfPages = steps.count
		pageIndicatorView.addSubview(pageIndicator)
		self.pageIndicator = pageIndicator

		showStep(at: 0, animated: false)
	}

	@objc public func show() {
		let window = window // Loads the nib
		window?.center()
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
	}

	// MARK: - Steps

	private var currentStep: OnboardingStepViewController {
		steps[currentStepIndex]
	}

	private func showStep(at index: Int, animated: Bool) {
		precondition(index < steps.count)

		let outgoing: OnboardingStepViewController? =
			(contentContainerView?.subviews.isEmpty == false) ? currentStep : nil

		let incoming = steps[index]
		currentStepIndex = index

		/* Steps populate their outlets in loadView(); make sure the view exists
		 before the step is asked to prepare it. */
		incoming.loadViewIfNeeded()
		incoming.stepWillAppear()

		guard let container = contentContainerView else {
			return
		}

		let incomingView = incoming.view
		incomingView.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(incomingView)

		NSLayoutConstraint.activate([
			incomingView.topAnchor.constraint(equalTo: container.topAnchor),
			incomingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			incomingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			incomingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])

		updateChrome(for: incoming)

		let outgoingView = outgoing?.view

		if animated == false || outgoingView == nil || outgoingView === incomingView {
			if outgoingView !== incomingView {
				outgoingView?.removeFromSuperview()
			}

			focusStep(incoming)
			return
		}

		transitioning = true
		incomingView.alphaValue = 0.0

		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.2
			context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

			outgoingView?.animator().alphaValue = 0.0
			incomingView.animator().alphaValue = 1.0
		} completionHandler: { [weak self] in
			Task { @MainActor [weak self] in
				outgoingView?.removeFromSuperview()
				outgoingView?.alphaValue = 1.0

				self?.transitioning = false
				self?.focusStep(incoming)
			}
		}
	}

	private func focusStep(_ step: OnboardingStepViewController) {
		if let responder = step.preferredFirstResponder {
			window?.makeFirstResponder(responder)
		}
	}

	private func updateChrome(for step: OnboardingStepViewController) {
		titleTextField.stringValue = step.stepTitle
		subtitleTextField.stringValue = step.stepSubtitle

		let isFirst = currentStepIndex == 0
		let isLast = currentStepIndex == (steps.count - 1)

		backButton.isHidden = isFirst
		skipButton.isHidden = step.skippable == false

		continueButton.title =
			isLast
				? OnboardingStrings.Window.finishButton
				: OnboardingStrings.Window.continueButton

		pageIndicator.currentPage = currentStepIndex
	}

	// MARK: - Actions

	@IBAction public func back(_: Any?) {
		if transitioning || currentStepIndex == 0 {
			return
		}

		showStep(at: currentStepIndex - 1, animated: true)
	}

	@IBAction public func continueToNextStep(_: Any?) {
		if transitioning {
			return
		}

		/* Commit any field still being edited. */
		window?.makeFirstResponder(nil)

		do {
			try currentStep.commit()
		} catch {
			let message = (error as? OnboardingStepError)?.message ?? error.localizedDescription

			if message.isEmpty == false, let window {
				TDCAlert.alertSheet(
					with: window,
					body: message,
					title: currentStep.stepTitle,
					defaultButton: PromptStrings.Action.confirmation,
					alternateButton: nil,
					otherButton: nil
				)
			}

			focusStep(currentStep)
			return
		}

		let nextIndex = currentStepIndex + 1

		if nextIndex < steps.count {
			showStep(at: nextIndex, animated: true)
			return
		}

		finish()
	}

	@IBAction public func skip(_: Any?) {
		closeAsCompleted()
	}

	@objc public func cancel(_ sender: Any?) {
		skip(sender)
	}

	@objc override public func cancelOperation(_ sender: Any?) {
		skip(sender)
	}

	// MARK: - Finishing

	private func closeAsCompleted() {
		TextualPreferences.setOnboardingCompleted(true)
		close()
	}

	private func finish() {
		if finished {
			return
		}

		finished = true

		applyIdentitySettings()
		applyAppearanceSettings()
		applyNotificationSettings()
		createClient()

		closeAsCompleted()
	}

	private func applyIdentitySettings() {
		if settings.nickname.isEmpty == false {
			TextualPreferences.setDefaultNickname(settings.nickname)
		}

		if settings.realName.isEmpty == false {
			TextualPreferences.setDefaultRealName(settings.realName)
		}
	}

	private func applyAppearanceSettings() {
		var reloadAction: PreferencesReloadAction = []

		/* The bundled chat styles are looked up by name. When a style is not
		 shipped in this build the current theme is left alone. */
		if let themeName = TPCThemeController.buildFilename(settings.styleName, for: .bundle),
		   SharedApplication.sharedThemeController().themeExists(themeName)
		{
			if TextualPreferences.themeName() != themeName {
				TextualPreferences.setThemeName(themeName)
				reloadAction.insert(.style)
			}
		} else {
			let styleName = settings.styleName

			onboardingLogger.info(
				"Chat style '\(styleName, privacy: .public)' is not bundled; keeping the current theme"
			)
		}

		let fontSize = OnboardingSettings.fontSize(for: settings.textSize)

		if TextualPreferences.themeChannelViewFontSize() != fontSize {
			TextualPreferences.setThemeChannelViewFontSize(fontSize)
			reloadAction.insert(.style)
		}

		if TextualPreferences.appearance() != settings.appearance {
			TextualPreferences.setAppearance(settings.appearance)
			reloadAction.insert(.appearance)
		}

		if reloadAction.isEmpty == false {
			TextualPreferences.performReloadAction(reloadAction)
		}
	}

	private func applyNotificationSettings() {
		TextualPreferences.setNotificationEnabled(settings.notifyOnHighlight, for: .highlight)
		TextualPreferences.setNotificationEnabled(settings.notifyOnPrivateMessage, for: .privateMessage)
		TextualPreferences.setNotificationEnabled(settings.notifyOnPrivateMessage, for: .newPrivateMessage)
		TextualPreferences.setSoundIsMuted(settings.playSounds == false)
	}

	private func createClient() {
		guard var config = settings.clientConfig else {
			return
		}

		config.nickname = settings.nickname

		if settings.realName.isEmpty == false {
			config.realName = settings.realName
		}

		if let alternateNickname = settings.alternateNickname, alternateNickname.isEmpty == false {
			config.alternateNicknames = [alternateNickname]
		}

		config.autoConnect = settings.connectWhenFinished

		config.channelList = settings.channelsToJoin.map(ChannelConfig.seed(withName:))

		/* Onboarding runs at launch, exactly when these are least likely to exist. */
		guard
			let world = AppController.shared.world,
			let mainWindow = AppController.shared.mainWindow
		else {
			onboardingLogger.error("Cannot create a connection before the world is ready")
			return
		}

		/* IRCClient.init(config:) moves the account password into the keychain. */
		let client = world.createClient(with: config, reload: true)

		mainWindow.expandClient(client)
		world.save()
		_ = mainWindow.reloadLoadingScreen()

		if settings.connectWhenFinished {
			client.connect()
		}

		client.selectFirstChannelInChannelList()
	}

	// MARK: - Window Delegate

	public func windowShouldClose(_: NSWindow) -> Bool {
		/* Closing the window is the same as skipping the rest of the flow. */
		TextualPreferences.setOnboardingCompleted(true)
		return true
	}

	public func windowWillClose(_: Notification) {
		delegate?.onboardingWindowControllerWillClose(self)
	}
}
