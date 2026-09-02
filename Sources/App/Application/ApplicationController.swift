/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os

private let terminationHistoricLogSaveTimeout: TimeInterval = 15.0

private let pluginsFinishedLoadingNotification = Notification.Name(
	"THOPluginManagerFinishedLoadingPluginsNotification"
)

/// AppKit ships `NSWorkspace.WillSleepMessage` but no power-off equivalent, so
/// the interop shape is spelled out here: the notification to bridge from, and
/// how to make the message. Declaring it as a `MainActorMessage` is what makes
/// Foundation deliver the power-off warning synchronously *on* the main actor
/// instead of handing a nonisolated block to a caller who has to assume.
private struct WorkspaceWillPowerOffMessage: NotificationCenter.MainActorMessage {
	typealias Subject = NSWorkspace

	static var name: Notification.Name {
		NSWorkspace.willPowerOffNotification
	}

	static func makeMessage(_: Notification) -> Self? {
		Self()
	}
}

/** What `applicationShouldTerminate` does with the request.

 Every route ends at `.terminateLater` and the three termination steps report
 back to NSApp themselves, so what is actually being decided is whether to
 start those steps, ask the user first, or leave a shutdown already in flight
 alone. */
enum ApplicationTerminationPolicy {
	enum Decision: Equatable {
		/// Termination is already running: do nothing and let it finish.
		case alreadyTerminating
		/// The confirmation sheet is on screen: the answer to that one decides
		/// this request too, so do not ask a second time.
		case alreadyDeciding
		/// Run the termination steps now.
		case begin
		/// Ask before quitting on top of a live connection.
		case confirm
	}

	static func decision(
		isTerminating: Bool,
		isAwaitingConfirmation: Bool,
		skipConfirmation: Bool,
		confirmQuitPreference: Bool,
		hasLiveConnection: Bool
	) -> Decision {
		if isTerminating {
			return .alreadyTerminating
		}

		if isAwaitingConfirmation {
			return .alreadyDeciding
		}

		if skipConfirmation || confirmQuitPreference == false || hasLiveConnection == false {
			return .begin
		}

		return .confirm
	}
}

@objc(TXMasterController)
@MainActor
public final class ApplicationController: NSObject, NSApplicationDelegate {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "General"
	)

	private static let terminationLogger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Termination"
	)

	private var hasInstalledMainWindow = false

	private var worldStorage: IRCWorld!
	private var mainWindowStorage: MainWindow!
	private weak var menuControllerStorage: MenuController?

	public private(set) var debugModeIsOn = false
	public private(set) var ghostModeIsOn = false
	public private(set) var applicationIsActive = false
	public private(set) var applicationIsLaunched = false
	public private(set) var applicationIsTerminating = false
	public private(set) var applicationIsChangingActiveState = false

	public var skipTerminateSave = false

	private var terminateHistoricLogSaveStarted = false
	private var terminateStepThreePerformed = false
	/// The safety net that unblocks NSTerminateLater if the historic-log
	/// service never answers.
	private var historicLogSaveTimeoutTask: Task<Void, Never>?
	private var skipTerminateConfirmation = false
	/// Raised while the quit confirmation sheet is on screen. Sheets stack, so
	/// without it a second ⌘Q queues a second sheet and both completions run:
	/// two shutdowns, or a cancel answered on top of one already in flight.
	private var terminationConfirmationIsPending = false
	private let notifications = NotificationSubscriptions()
	private lazy var resourceFileImporter = ResourceFileImporter()

	/// IUO preserves the established launch-time contract while allowing nil in tests.
	@objc public var mainWindow: MainWindow! {
		get { mainWindowStorage }
		set { mainWindowStorage = newValue }
	}

	@objc public weak var menuController: MenuController? {
		get { menuControllerStorage }
		set { menuControllerStorage = newValue }
	}

	public var world: IRCWorld! {
		get { worldStorage }
		set { worldStorage = newValue }
	}

	public var terminatingClientCount: UInt = 0 {
		didSet {
			if terminatingClientCount != 0 || applicationIsTerminating == false {
				return
			}

			Task { @MainActor [weak self] in
				self?.terminatingClientsDidFinish()
			}
		}
	}

	// MARK: - Initialization

	override public init() {
		super.init()

		AppController.setCurrent(self)
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

	/// Builds the main window after the programmatic application and menu graph.
	private func installMainWindow() {
		guard hasInstalledMainWindow == false else {
			return
		}

		hasInstalledMainWindow = true

		TextualPreferences.initPreferences()

		_ = SharedApplication.sharedAppearance()

		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 477),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Glasstual"
		window.identifier = NSUserInterfaceItemIdentifier("TVCMainWindow")
		window.contentMinSize = MainWindowConstants.minimumContentSize
		window.setFrameAutosaveName("Main Window")
		window.tabbingMode = .disallowed
		window.collectionBehavior.insert(.fullScreenPrimary)
		window.isReleasedWhenClosed = false
		window.setAccessibilityLabel(AccessibilityStrings.mainWindow)
		mainWindowStorage = window
		window.configure()
	}

	public func applicationWakeStepOne() {
		world = IRCWorld()
	}

	/** Hands the IRC layer the window, the menus and this controller, and makes
	 both of the first two observers of the world. Everything the connection code
	 used to reach for through `AppController.shared` arrives this way. */
	func installClientServices() {
		let services = ClientEnvironment.shared.services
		services.output = mainWindowStorage
		services.menu = menuControllerStorage
		services.applicationState = self
		services.world = worldStorage

		if let mainWindowStorage {
			worldStorage?.addObserver(mainWindowStorage)
		}

		if let menuControllerStorage {
			worldStorage?.addObserver(menuControllerStorage)
		}
	}

	public func applicationWakeStepTwo() {
		CommandIndex.populateCommandIndex()

		SystemInformation.beginObservingSleepState()

		prepareNetworkReachabilityNotifier()

		let workspaceCenter = NSWorkspace.shared.notificationCenter
		notifications.observe(NSWorkspace.didWakeNotification, center: workspaceCenter) { [weak self] notification in
			self?.computerDidWakeUp(notification)
		}
		notifications.observeSynchronously(NSWorkspace.WillSleepMessage.self, center: workspaceCenter) { [weak self] in
			self?.computerWillSleep()
		}
		notifications
			.observeSynchronously(WorkspaceWillPowerOffMessage.self, center: workspaceCenter) { [weak self] in
				self?.computerWillPowerOff()
			}
		notifications
			.observe(NSWorkspace.screensDidWakeNotification, center: workspaceCenter) { [weak self] notification in
				self?.computerScreenDidWake(notification)
			}
		notifications
			.observe(NSWorkspace.screensDidSleepNotification, center: workspaceCenter) { [weak self] notification in
				self?.computerScreenWillSleep(notification)
			}
		notifications.observe(pluginsFinishedLoadingNotification) { [weak self] notification in
			self?.pluginsFinishedLoading(notification)
		}

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

		Task {
			await ResourceManager.copyResourcesToApplicationSupportFolder()
		}

		/* Load plugins last so that -applicationDidFinishLaunching is posted
		 only once they have loaded and everything else has been setup. */
		SharedApplication.sharedPluginManager().loadPlugins()
	}

	private func pluginsFinishedLoading(_: Notification) {
		completeApplicationLaunch()
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
		SharedApplication.sharedApplicationScenes().install(in: NSApp)

		#if !DEBUG
			/* Asking the user about another running copy needs an alert, and
			 an alert needs NSApp — so this cannot run before
			 NSApplicationMain, which is where it used to live. */
			if Application.shouldContinueLaunching() == false {
				exit(EXIT_SUCCESS)
			}
		#endif

		/* UserNotifications.framework wants delegation set before app has
		 finished launching. A simple access to the singleton will set this
		 for us which we can just do here. */
		_ = SharedApplication.sharedNotificationController()
	}

	public func applicationDidFinishLaunching(_: Notification) {
		installMainWindow()
		mainWindow.makeMain()
		mainWindow.makeKeyAndOrderFront(nil)
	}

	private func completeApplicationLaunch() {
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
		guard OnboardingSession.shouldPresentOnLaunch() else {
			return
		}

		menuController?.showOnboardingWindow(nil)
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
		if SharedApplication.sharedPluginManager().pluginsLoaded {
			SharedApplication.sharedPluginManager().refreshScriptCommands()
		}
	}

	public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		if applicationIsTerminating {
			return false
		}

		mainWindow.makeKeyAndOrderFront(nil)
		return true
	}

	/** Scripts and extensions the user opened from the Finder. The declared
	 document types used to name an `NSDocument` subclass, whose nonisolated
	 `read(from:ofType:)` had to assume the main actor before it could put an
	 alert on screen; this delegate method is isolated by declaration. */
	public func application(_: NSApplication, open urls: [URL]) {
		resourceFileImporter.open(urls)
	}

	public func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
		/* The main window encodes its selection with secure coding. */
		true
	}

	// MARK: - NSApplication Terminate Procedure

	public func applicationDockMenu(_: NSApplication) -> NSMenu? {
		menuController?.dockMenu
	}

	/** The answer is always `.terminateLater`: every route to shutting down
	 runs the three termination steps, and step three is what reports back to
	 NSApp. */
	public func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
		let stillConnected = world.clientList.contains { $0.isConnecting || $0.isConnected }

		switch ApplicationTerminationPolicy.decision(
			isTerminating: applicationIsTerminating,
			isAwaitingConfirmation: terminationConfirmationIsPending,
			skipConfirmation: skipTerminateConfirmation,
			confirmQuitPreference: Preferences.Connection.confirmQuit.value,
			hasLiveConnection: stillConnected
		) {
		case .alreadyTerminating:
			/* Termination is already under way. Answering .terminateNow here
			 used to schedule step one a second time, tearing everything down
			 twice. */
			Self.terminationLogger.debug("Termination is already in progress")
		case .alreadyDeciding:
			Self.terminationLogger.debug("Termination confirmation is already on screen")
		case .begin:
			Task { @MainActor [weak self] in
				self?.performApplicationTerminationStepOne()
			}
		case .confirm:
			presentTerminationConfirmation()
		}

		return .terminateLater
	}

	/// The sheet's completion reports to NSApp and begins termination itself.
	private func presentTerminationConfirmation() {
		terminationConfirmationIsPending = true

		Alerts.alertSheet(
			body: PromptStrings.Application.quitBody,
			title: PromptStrings.Application.quitTitle,
			defaultButton: PromptStrings.Application.quitButtonTitle,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: nil
		) { [weak self] outcome in
			self?.terminationConfirmationIsPending = false

			let result = outcome.response == .default

			Self.terminationLogger.debug("Perform termination: \(result)")

			if result == false {
				NSApp.reply(toApplicationShouldTerminate: false)
				return
			}

			self?.performApplicationTerminationStepOne()
		}
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

				Task { @MainActor [weak self] in
					self?.completeHistoricLogSaveAndContinueTermination()
				}
			}

		/* Safety net: should historic-log shutdown never finish, do not
		 leave the application hanging in NSTerminateLater forever. */
		historicLogSaveTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(terminationHistoricLogSaveTimeout))

			guard Task.isCancelled == false, let self else { return }

			completeHistoricLogSaveAndContinueTermination()
		}
	}

	private func completeHistoricLogSaveAndContinueTermination() {
		historicLogSaveTimeoutTask?.cancel()
		historicLogSaveTimeoutTask = nil

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
		/* Nothing may run the teardown twice: a second pass nils the delegate
		 again and re-seeds `terminatingClientCount` while the first round's
		 clients are still reporting in. */
		guard applicationIsTerminating == false else {
			Self.terminationLogger.debug("Step one skipped; termination is already in progress")
			return
		}

		Self.terminationLogger.debug("Step one entry")

		applicationIsTerminating = true

		SharedApplication.sharedAppearance().prepareForApplicationTermination()

		mainWindow.prepareForApplicationTermination()

		Self.terminationLogger.debug("Giving up shared application delegation")
		NSApp.delegate = nil

		Self.terminationLogger.debug("Cancelling lifecycle notification subscriptions")
		notifications.cancelAll()

		Self.terminationLogger.debug("Removing AppleScript event observer")
		NSAppleEventManager.shared().removeEventHandler(
			forEventClass: AEEventClass(kInternetEventClass),
			andEventID: AEEventID(kAEGetURL)
		)

		Self.terminationLogger.debug("Stopping reachability notifier")
		SharedApplication.sharedNetworkReachabilityNotifier().stopNotifier()

		Self.terminationLogger.debug("Stopping speech synthesizer")
		SharedApplication.existingSpeechSynthesizer()?.isStopped = true

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

		Self.terminationLogger.debug("Unloading plugins")
		SharedApplication.sharedPluginManager().unloadPlugins()

		SoundPlayer.prepareForApplicationTermination()

		Self.terminationLogger.debug("Saving running internal")
		ApplicationInfo.saveTimeIntervalSinceApplicationInstall()

		Self.terminationLogger.debug("Terminate")
		NSApp.reply(toApplicationShouldTerminate: true)
	}

	/** Quit without arguing about it — the machine is powering off.

	 This used to set `applicationIsTerminating` itself, which made
	 `applicationShouldTerminate` read termination as already under way and
	 answer `.terminateLater` without ever running step one: no client left IRC
	 gracefully and no historic log was saved. The flag belongs to step one;
	 all this path skips is the confirmation sheet. */
	public func terminateGracefully() {
		skipTerminateConfirmation = true

		NSApp.terminate(nil)
	}

	// MARK: - NSWorkspace Notifications

	@objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
		guard let stringValue = event.atIndex(1)?.stringValue else {
			return
		}

		ApplicationLinkHandler.open(stringValue)
	}

	private func computerScreenWillSleep(_: Notification) {
		Self.logger.log("Preparing for screen sleep")
		world.prepareForScreenSleep()
	}

	private func computerScreenDidWake(_: Notification) {
		Self.logger.log("Waking from screen sleep")
		world.wakeFromScreenSleep()
	}

	private func computerWillSleep() {
		Self.logger.log("Preparing for sleep")

		world.prepareForSleep()

		SharedApplication.sharedSpeechSynthesizer().isStopped = true
		SharedApplication.sharedSpeechSynthesizer().clearQueue()

		SharedApplication.sharedNetworkReachabilityNotifier().stopNotifier()
	}

	private func computerDidWakeUp(_: Notification) {
		Self.logger.log("Waking from sleep")

		SharedApplication.sharedSpeechSynthesizer().isStopped = false
		_ = SharedApplication.sharedNetworkReachabilityNotifier().startNotifier()

		world.autoConnect(afterWakeup: true)
	}

	private func computerWillPowerOff() {
		terminateGracefully()
	}
}

/// The application state the IRC layer branches on, behind a seam so that the
/// connection code does not name the application controller.
extension ApplicationController: ClientApplicationState {
	func noteClientDidFinishTerminating() {
		/* A client that reports in more than once must not trap the subtraction
		 on an unsigned count. */
		guard terminatingClientCount > 0 else {
			return
		}

		terminatingClientCount -= 1
	}
}
