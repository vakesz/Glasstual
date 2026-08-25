/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import os

private let terminationHistoricLogSaveTimeout: TimeInterval = 15.0

private let pluginsFinishedLoadingNotification = Notification.Name(
	"THOPluginManagerFinishedLoadingPluginsNotification"
)

@objc(TXMasterController)
public final class MasterController: NSObject, NSApplicationDelegate {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "General"
	)

	private static let terminationLogger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Termination"
	)

	private nonisolated(unsafe) static var awakeFromNibCalled = false

	private var worldStorage: IRCWorld!
	private var mainWindowStorage: TVCMainWindow!
	private weak var menuControllerStorage: TXMenuController?

	@objc public private(set) var debugModeIsOn = false
	@objc public private(set) var ghostModeIsOn = false
	@objc public private(set) var applicationIsActive = false
	@objc public private(set) var applicationIsLaunched = false
	@objc public private(set) var applicationIsTerminating = false
	@objc public private(set) var applicationIsChangingActiveState = false

	@objc public var skipTerminateSave = false

	private var terminateHistoricLogSaveStarted = false
	private var terminateStepThreePerformed = false

	/** Nib connects these via KVC (`setValue:forKey:`). IUO matches the
	 ObjC nonnull headers while still allowing nil before wake / in tests. */
	@objc public var mainWindow: TVCMainWindow! {
		get { mainWindowStorage }
		set { mainWindowStorage = newValue }
	}

	@objc public weak var menuController: TXMenuController? {
		get { menuControllerStorage }
		set { menuControllerStorage = newValue }
	}

	@objc public var world: IRCWorld! {
		get { worldStorage }
		set { worldStorage = newValue }
	}

	@objc public var terminatingClientCount: UInt = 0 {
		didSet {
			if terminatingClientCount != 0 || applicationIsTerminating == false {
				return
			}

			XRPerformBlockAsynchronouslyOnMainQueue { [weak self] in
				self?.terminatingClientsDidFinish()
			}
		}
	}

	// MARK: - Initialization

	override public init() {
		super.init()

		NSObject.setGlobalMasterControllerClassReference(self)
		prepareInitialState()
	}

	private func prepareInitialState() {
		Logging.setDefaultSubsystem(toMainBundleCategory: "General")

		let keyboardKeys = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

		if keyboardKeys.contains(.control) {
			debugModeIsOn = true
			Self.logger.info("Launching in debug mode")
		}

		#if DEBUG
			ghostModeIsOn = true // Do not use auto connect during debug
		#else
			if keyboardKeys.contains(.shift) {
				ghostModeIsOn = true
				Self.logger.info("Launching without auto connecting to the configured servers")
			}
		#endif
	}

	override public func awakeFromNib() {
		guard Self.awakeFromNibCalled == false else {
			return
		}

		Self.awakeFromNibCalled = true
		awakeFromNibInternal()
	}

	private func awakeFromNibInternal() {
		TPCPreferences.initPreferences()

		_ = SharedApplication.sharedAppearance()

		/* Wait until -awakeFromNib to wake the window so that the menu
		 controller created by the main nib has time to load. */
		Bundle.main.loadNibNamed("TVCMainWindow", owner: self, topLevelObjects: nil)
	}

	@objc
	public func applicationWakeStepOne() {
		world = IRCWorld()
	}

	@objc
	public func applicationWakeStepTwo() {
		IRCCommandIndex.populateCommandIndex()

		prepareNetworkReachabilityNotifier()

		let workspaceCenter = NSWorkspace.shared.notificationCenter
		workspaceCenter.addObserver(
			self,
			selector: #selector(computerDidWakeUp(_:)),
			name: NSWorkspace.didWakeNotification,
			object: nil
		)
		workspaceCenter.addObserver(
			self,
			selector: #selector(computerWillSleep(_:)),
			name: NSWorkspace.willSleepNotification,
			object: nil
		)
		workspaceCenter.addObserver(
			self,
			selector: #selector(computerWillPowerOff(_:)),
			name: NSWorkspace.willPowerOffNotification,
			object: nil
		)
		workspaceCenter.addObserver(
			self,
			selector: #selector(computerScreenDidWake(_:)),
			name: NSWorkspace.screensDidWakeNotification,
			object: nil
		)
		workspaceCenter.addObserver(
			self,
			selector: #selector(computerScreenWillSleep(_:)),
			name: NSWorkspace.screensDidSleepNotification,
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(pluginsFinishedLoading(_:)),
			name: pluginsFinishedLoadingNotification,
			object: nil
		)

		NSAppleEventManager.shared().setEventHandler(
			self,
			andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
			forEventClass: AEEventClass(kInternetEventClass),
			andEventID: AEEventID(kAEGetURL)
		)

		NSColorPanel.setPickerMask([
			.rgbModeMask,
			.grayModeMask,
			.colorListModeMask,
			.wheelModeMask,
			.crayonModeMask,
		])
		NSColorPanel.shared.showsAlpha = true

		DispatchQueue.global(qos: .background).async {
			ResourceManager.copyResourcesToApplicationSupportFolder()
		}

		/* Load plugins last so that -applicationDidFinishLaunching is posted
		 only once they have loaded and everything else has been setup. */
		SharedApplication.sharedPluginManager().loadPlugins()
	}

	@objc
	private func pluginsFinishedLoading(_: Notification) {
		applicationDidFinishLaunching()
	}

	// MARK: - Services

	private func prepareNetworkReachabilityNotifier() {
		let notifier = SharedApplication.sharedNetworkReachabilityNotifier()

		notifier.reachableBlock = { [weak self] _ in
			self?.world.noteReachabilityChanged(true)
		}

		notifier.unreachableBlock = { [weak self] _ in
			self?.world.noteReachabilityChanged(false)
		}

		_ = notifier.startNotifier()
	}

	// MARK: - NSApplication Delegate

	public func applicationWillFinishLaunching(_: Notification) {
		/* UserNotifications.framework wants delegation set before app has
		 finished launching. A simple access to the singleton will set this
		 for us which we can just do here. */
		Self.logger.debug(
			"Preparing notification controller singleton: \(SharedApplication.sharedNotificationController().description, privacy: .public)"
		)
	}

	private func applicationDidFinishLaunching() {
		applicationIsLaunched = true

		if mainWindow.reloadLoadingScreen() {
			world.autoConnect(afterWakeup: false)
		}

		presentOnboardingIfNeeded()
	}

	/** First launch: no client has been configured and the setup flow has not
	 been completed or skipped before. The flow is shown on top of the main
	 window's "add a server" placeholder. */
	private func presentOnboardingIfNeeded() {
		let shouldPresent = MainActor.assumeIsolated {
			OnboardingWindowController.shouldPresentOnLaunch()
		}

		guard shouldPresent else {
			return
		}

		nonisolated(unsafe) let menu = menuController
		MainActor.assumeIsolated {
			menu?.showOnboardingWindow(nil)
		}
	}

	public func applicationWillResignActive(_: Notification) {
		applicationIsChangingActiveState = true
	}

	public func applicationWillBecomeActive(_: Notification) {
		applicationIsChangingActiveState = true
	}

	public func applicationDidResignActive(_: Notification) {
		applicationIsActive = false
		applicationIsChangingActiveState = false
	}

	public func applicationDidBecomeActive(_: Notification) {
		applicationIsActive = true
		applicationIsChangingActiveState = false
	}

	public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		if applicationIsTerminating {
			return false
		}

		mainWindow.makeKeyAndOrderFront(nil)
		return true
	}

	public func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
		if applicationIsTerminating {
			return false
		}

		mainWindow.makeKeyAndOrderFront(nil)
		return true
	}

	public func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
		/* The main window encodes its selection with secure coding. */
		true
	}

	// MARK: - NSApplication Terminate Procedure

	public func applicationDockMenu(_: NSApplication) -> NSMenu? {
		menuController?.dockMenu
	}

	/** Returns `.terminateNow` when termination may begin immediately,
	 `.terminateCancel` when refused outright. When a confirmation is needed
	 the answer is deferred: the sheet's completion reports to NSApp and
	 begins termination itself. */
	private func queryTerminate() -> NSApplication.TerminateReply {
		if applicationIsTerminating {
			Self.terminationLogger.debug("Termination is already in progress")
			return .terminateNow
		}

		if TPCPreferences.confirmQuit() == false {
			return .terminateNow
		}

		var stillConnected = false

		for client in world.clientList {
			if client.isConnecting || client.isConnected {
				stillConnected = true
			}
		}

		if stillConnected == false {
			return .terminateNow
		}

		TDCAlert.alertSheet(
			with: mainWindow,
			body: LocalizedKey("Prompts[77u-vp]"),
			title: LocalizedKey("Prompts[6vj-2p]"),
			defaultButton: LocalizedKey("Prompts[1bf-k0]"),
			alternateButton: LocalizedKey("Prompts[qso-2g]"),
			otherButton: nil
		) { [weak self] buttonClicked, _, _ in
			let result = buttonClicked == .default

			Self.terminationLogger.debug("Perform termination: \(result)")

			if result == false {
				NSApp.reply(toApplicationShouldTerminate: false)
				return
			}

			self?.performApplicationTerminationStepOne()
		}

		return .terminateLater
	}

	public func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
		let reply = queryTerminate()

		if reply != .terminateNow {
			return reply
		}

		XRPerformBlockAsynchronouslyOnMainQueue { [weak self] in
			self?.performApplicationTerminationStepOne()
		}

		return .terminateLater
	}

	private func terminatingClientsDidFinish() {
		if applicationIsTerminating == false || terminateHistoricLogSaveStarted {
			return
		}

		terminateHistoricLogSaveStarted = true

		Self.terminationLogger.debug("All clients finished; saving historic log")

		LogControllerHistoricLogFile.shared()
			.prepareForApplicationTermination { [weak self] in
				guard let self else {
					return
				}

				perform(
					#selector(completeHistoricLogSaveAndContinueTermination),
					on: .main,
					with: nil,
					waitUntilDone: false
				)
			}

		/* Safety net: should the historic log service never answer, do not
		 leave the application hanging in NSTerminateLater forever. */
		perform(
			#selector(completeHistoricLogSaveAndContinueTermination),
			with: nil,
			afterDelay: terminationHistoricLogSaveTimeout
		)
	}

	@objc
	private func completeHistoricLogSaveAndContinueTermination() {
		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(completeHistoricLogSaveAndContinueTermination),
			object: nil
		)

		if terminateStepThreePerformed {
			return
		}

		if applicationIsTerminating == false {
			return
		}

		if terminateHistoricLogSaveStarted == false {
			return
		}

		terminateStepThreePerformed = true
		performApplicationTerminationStepThree()
	}

	private func performApplicationTerminationStepOne() {
		Self.terminationLogger.debug("Step one entry")

		applicationIsTerminating = true

		nonisolated(unsafe) let appearance = SharedApplication.sharedAppearance()
		MainActor.assumeIsolated {
			appearance.prepareForApplicationTermination()
		}

		mainWindow.prepareForApplicationTermination()

		Self.terminationLogger.debug("Giving up shared application delegation")
		NSApp.delegate = nil

		Self.terminationLogger.debug("Removing workspace notification center observer")
		NSWorkspace.shared.notificationCenter.removeObserver(self)

		Self.terminationLogger.debug("Removing shared notification center observer")
		NotificationCenter.default.removeObserver(self)

		Self.terminationLogger.debug("Removing AppleScript event observer")
		NSAppleEventManager.shared().removeEventHandler(
			forEventClass: AEEventClass(kInternetEventClass),
			andEventID: AEEventID(kAEGetURL)
		)

		Self.terminationLogger.debug("Stopping reachability notifier")
		SharedApplication.sharedNetworkReachabilityNotifier().stopNotifier()

		Self.terminationLogger.debug("Stopping speech synthesizer")
		SharedApplication.existingSpeechSynthesizer()?.isStopped = true

		LogControllerInlineMediaService.shared().prepareForApplicationTermination()

		menuController?.prepareForApplicationTermination()

		performApplicationTerminationStepTwo()
	}

	private func performApplicationTerminationStepTwo() {
		guard applicationIsTerminating else {
			return
		}

		Self.terminationLogger.debug("Step two entry")

		/* We want certain things to 100% happen before the app completely closes.
		 Notable actions: gracefully leaving IRC, saving historic logs, etc.
		 Each client decrements -terminatingClientCount once it has finished and
		 the setter continues with step three once the count reaches zero and the
		 historic log has been saved. With no clients, assigning zero here
		 continues immediately. */
		terminatingClientCount = world.clientCount

		world.prepareForApplicationTermination()
	}

	private func performApplicationTerminationStepThree() {
		guard applicationIsTerminating else {
			return
		}

		Self.terminationLogger.debug("Step three entry")

		if skipTerminateSave == false {
			Self.terminationLogger.debug("Saving IRC world")
			world.save()
		}

		Self.terminationLogger.debug("Suspending member list dispatch queue")
		ChannelMemberList.suspendSerialQueues()

		Self.terminationLogger.debug("Unloading plugins")
		SharedApplication.sharedPluginManager().unloadPlugins()

		SharedApplication.sharedWindowController().prepareForApplicationTermination()
		SharedApplication.sharedThemeController().prepareForApplicationTermination()

		Self.terminationLogger.debug("Saving running internal")
		ApplicationInfo.saveTimeIntervalSinceApplicationInstall()

		Self.terminationLogger.debug("Terminate")
		NSApp.reply(toApplicationShouldTerminate: true)
	}

	@objc
	public func terminateGracefully() {
		applicationIsTerminating = true
		NSApp.terminate(nil)
	}

	// MARK: - NSWorkspace Notifications

	@objc
	private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
		guard let stringValue = event.atIndex(1)?.stringValue else {
			return
		}

		Extras.parseIRCProtocolURI(stringValue, withDescriptor: event)
	}

	@objc
	private func computerScreenWillSleep(_: Notification) {
		Self.logger.log("Preparing for screen sleep")
		world.prepareForScreenSleep()
	}

	@objc
	private func computerScreenDidWake(_: Notification) {
		Self.logger.log("Waking from screen sleep")
		world.wakeFromScreenSleep()
	}

	@objc
	private func computerWillSleep(_: Notification) {
		Self.logger.log("Preparing for sleep")

		world.prepareForSleep()

		SharedApplication.sharedSpeechSynthesizer().isStopped = true
		SharedApplication.sharedSpeechSynthesizer().clearQueue()

		SharedApplication.sharedNetworkReachabilityNotifier().stopNotifier()
	}

	@objc
	private func computerDidWakeUp(_: Notification) {
		Self.logger.log("Waking from sleep")

		SharedApplication.sharedSpeechSynthesizer().isStopped = false
		_ = SharedApplication.sharedNetworkReachabilityNotifier().startNotifier()

		world.autoConnect(afterWakeup: true)
	}

	@objc
	private func computerWillPowerOff(_: Notification) {
		terminateGracefully()
	}
}
