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
		LocalizedKey("TDCOnboardingWindow[ob1-pg]", currentPage + 1, numberOfPages)
	}
}

// MARK: - Window Controller

@objc(TDCOnboardingWindowController)
@MainActor
public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
	@objc public weak var delegate: AnyObject?

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

	@objc public class func shouldPresentOnLaunch() -> Bool {
		if TPCPreferences.onboardingCompleted() {
			return false
		}

		return (NSObject.masterController().world?.clientCount ?? 0) == 0
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
		settings.textSize = OnboardingSettings.textSize(forFontSize: TPCPreferences.themeChannelViewFontSize())
		settings.appearance = TPCPreferences.appearance()

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

		window.title = LocalizedKey("TDCOnboardingWindow[ob1-wt]")
		window.styleMask.insert(.fullSizeContentView)
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden

		iconImageView.image = NSApp.applicationIconImage

		subtitleTextField.maximumNumberOfLines = 2
		subtitleTextField.preferredMaxLayoutWidth = 560

		skipButton.title = LocalizedKey("TDCOnboardingWindow[ob1-sk]")
		backButton.title = LocalizedKey("TDCOnboardingWindow[ob1-bk]")

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
			outgoingView?.removeFromSuperview()
			outgoingView?.alphaValue = 1.0

			self?.transitioning = false
			self?.focusStep(incoming)
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
				? LocalizedKey("TDCOnboardingWindow[ob1-fn]")
				: LocalizedKey("TDCOnboardingWindow[ob1-ct]")

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

		var errorDescription: NSString?
		if currentStep.commit(errorDescription: &errorDescription) == false {
			if let errorDescription, errorDescription.length > 0, let window {
				TDCAlert.alertSheet(
					with: window,
					body: errorDescription as String,
					title: currentStep.stepTitle,
					defaultButton: LocalizedKey("Prompts[c7s-dq]"),
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
		TPCPreferences.setOnboardingCompleted(true)
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
			TPCPreferencesUserDefaults.shared().set(settings.nickname, forKey: "DefaultIdentity -> Nickname")
		}

		if settings.realName.isEmpty == false {
			TPCPreferencesUserDefaults.shared().set(settings.realName, forKey: "DefaultIdentity -> Realname")
		}
	}

	private func applyAppearanceSettings() {
		var reloadAction: TPCPreferencesReloadAction = []

		/* The bundled chat styles are looked up by name. When a style is not
		 shipped in this build the current theme is left alone. */
		if let themeName = TPCThemeController.buildFilename(settings.styleName, for: .bundle),
		   TXSharedApplication.sharedThemeController().themeExists(themeName)
		{
			if TPCPreferences.themeName() != themeName {
				TPCPreferences.setThemeName(themeName)
				reloadAction.insert(.style)
			}
		} else {
			onboardingLogger.info(
				"Chat style '\(settings.styleName, privacy: .public)' is not bundled; keeping the current theme"
			)
		}

		let fontSize = OnboardingSettings.fontSize(for: settings.textSize)

		if TPCPreferences.themeChannelViewFontSize() != fontSize {
			TPCPreferences.setThemeChannelViewFontSize(fontSize)
			reloadAction.insert(.style)
		}

		if TPCPreferences.appearance() != settings.appearance {
			TPCPreferences.setAppearance(settings.appearance)
			reloadAction.insert(.appearance)
		}

		if reloadAction.isEmpty == false {
			TPCPreferences.performReloadAction(reloadAction)
		}
	}

	private func applyNotificationSettings() {
		TPCPreferences.setNotificationEnabled(settings.notifyOnHighlight, forEvent: .highlight)
		TPCPreferences.setNotificationEnabled(settings.notifyOnPrivateMessage, forEvent: .privateMessage)
		TPCPreferences.setNotificationEnabled(settings.notifyOnPrivateMessage, forEvent: .newPrivateMessage)
		TPCPreferences.setSoundIsMuted(settings.playSounds == false)
	}

	private func createClient() {
		guard let config = settings.clientConfig else {
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

		var channelList: [IRCChannelConfig] = []
		channelList.reserveCapacity(settings.channelsToJoin.count)

		for channelName in settings.channelsToJoin {
			channelList.append(IRCChannelConfig.seed(withName: channelName))
		}

		config.channelList = channelList

		let world = NSObject.masterController().world!
		let mainWindow = NSObject.masterController().mainWindow!

		/* -initWithConfig: moves the account password into the keychain. */
		let client = world.createClient(with: config.copy() as! IRCClientConfig, reload: true)

		mainWindow.expand(client)
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
		TPCPreferences.setOnboardingCompleted(true)
		return true
	}

	public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("onboardingWindowControllerWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
