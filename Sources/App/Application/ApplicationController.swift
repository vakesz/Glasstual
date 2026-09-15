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

/** How far shutdown has got.

 One value instead of the five booleans that used to answer for it, each of
 which could disagree with the others: a stage only ever moves forward, and
 every step reads the same value to decide whether its work has already been
 done. */
enum ApplicationTerminationStage: Int, Comparable, Sendable {
	/// Nothing has asked the application to quit.
	case running
	/// The quit confirmation is on screen and its answer decides.
	case confirming
	/// Clients are leaving IRC.
	case disconnecting
	/// The transcript files and the history store are being flushed.
	case savingLogs
	/// `NSApp` has been told it may quit.
	case finished

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
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
		/// The confirmation sheet is on screen, but this request cannot wait for
		/// an answer. Take the sheet down and run the termination steps.
		case overrideConfirmation
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

		/* The machine powering off cannot wait for a question the reader may
		 never come back to answer. */
		if isAwaitingConfirmation {
			return skipConfirmation ? .overrideConfirmation : .alreadyDeciding
		}

		if skipConfirmation || confirmQuitPreference == false || hasLiveConnection == false {
			return .begin
		}

		return .confirm
	}
}

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

	public private(set) var ghostModeIsOn = false
	public private(set) var applicationIsLaunched = false

	/// Teardown has begun: nothing may act on the connection tree any more.
	public var applicationIsTerminating: Bool {
		terminationStage >= .disconnecting
	}

	private var terminationStage: ApplicationTerminationStage = .running
	/// The two log drains still running. Step three waits for both, or for the
	/// deadline, whichever comes first.
	private var pendingLogDrains = 0
	/// Bounds both history persistence and the independent transcript-file drain.
	private var historicLogSaveTimeoutTask: Task<Void, Never>?
	private var skipTerminateConfirmation = false
	/// The quit confirmation while it is on screen. Cancelling it takes the
	/// sheet down without its answer being acted on.
	private var terminationConfirmation: Task<Void, Never>?
	private let notifications = NotificationSubscriptions()
	private lazy var resourceFileImporter = ResourceFileImporter()

	/// IUO preserves the established launch-time contract while allowing nil in tests.
	public var mainWindow: MainWindow!
	public weak var menuController: MenuController?
	public var world: World!

	public var terminatingClientCount: UInt = 0 {
		didSet {
			if terminatingClientCount != 0 || applicationIsTerminating == false {
				return
			}

			Task { [weak self] in
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

		#if DEBUG
			ghostModeIsOn = true // Do not use auto connect during debug
		#else
			let keyboardKeys = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
			if keyboardKeys.contains(.shift) {
				ghostModeIsOn = true
				Self.logger.info("Launching without auto connecting to the configured servers")
			}
		#endif
	}

	/** Builds the main window after the programmatic application and menu graph.

	 It has to exist before `applicationDidFinishLaunching`, because AppKit
	 restores windows before that call. A restoration class with no window to
	 hand back restores nothing, so the frame, full screen and the Space were
	 all lost. */
	private func installMainWindow() {
		guard hasInstalledMainWindow == false else {
			return
		}

		hasInstalledMainWindow = true

		TextualPreferences.initPreferences()

		_ = SharedApplication.sharedAppearance()

		let window = MainWindow(
			contentRect: NSRect(origin: .zero, size: MainWindowConstants.minimumContentSize),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = ApplicationInfo.applicationName()
		window.identifier = NSUserInterfaceItemIdentifier("TVCMainWindow")
		window.contentMinSize = MainWindowConstants.minimumContentSize
		window.setFrameAutosaveName("Main Window")
		window.tabbingMode = .disallowed
		window.collectionBehavior.insert(.fullScreenPrimary)
		window.isReleasedWhenClosed = false
		window.setAccessibilityLabel(AccessibilityStrings.mainWindow)
		mainWindow = window
		SheetPresentation.host = window
		window.configure()
	}

	public func applicationWakeStepOne() {
		world = World()
	}

	/** Hands the IRC layer the window, the menus and this controller, and makes
	 both of the first two observers of the world. Everything the connection code
	 used to reach for through `AppController.shared` arrives this way. */
	func installClientServices() {
		let services = ClientEnvironment.shared.services
		services.output = mainWindow
		services.menu = menuController
		services.channelList = SharedApplication.sharedApplicationScenes()
		services.applicationState = self
		services.world = world

		if let mainWindow {
			world?.addObserver(mainWindow)
		}

		if let menuController {
			world?.addObserver(menuController)
		}
	}

	public func applicationWakeStepTwo() {
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
		notifications.observe(PluginManager.finishedLoadingNotification) { [weak self] notification in
			self?.pluginsFinishedLoading(notification)
		}

		NSAppleEventManager.shared().setEventHandler(
			self,
			andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
			forEventClass: AEEventClass(kInternetEventClass),
			andEventID: AEEventID(kAEGetURL)
		)

		/* The mask has to be set before anything creates the shared panel, which
		 is the only reason a colour-picker detail is settled at launch. The
		 panel itself is not touched here: reading `NSColorPanel.shared` builds
		 the whole system picker, and its colour wheel draws through CoreImage,
		 so every launch loaded Metal and its shader caches for a picker most
		 sessions never open. Each presenter configures the panel it shows —
		 the formatting menu turns alpha off, a SwiftUI `ColorPicker` sets it
		 from `supportsOpacity`. */
		NSColorPanel.setPickerMask([
			.rgbModeMask,
			.grayModeMask,
			.colorListModeMask,
			.wheelModeMask,
			.crayonModeMask,
		])

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
		/* A second copy used to be met with a modal warning that the
		 preferences "may become corrupted". `LSMultipleInstancesProhibited`
		 means there is never a second copy to warn about: Launch Services
		 activates the one that is already running. */
		SharedApplication.sharedApplicationScenes().install(in: NSApp)

		/* UserNotifications.framework wants delegation set before app has
		 finished launching. A simple access to the singleton will set this
		 for us which we can just do here. */
		_ = SharedApplication.sharedNotificationController()

		installMainWindow()
	}

	public func applicationDidFinishLaunching(_: Notification) {
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

		SharedApplication.sharedApplicationScenes().openOnboarding()
	}

	/* The delegate stays attached until the process exits. The callbacks below
	 can therefore arrive during termination, and they must not start work that
	 teardown is already undoing. */

	public func applicationDidBecomeActive(_: Notification) {
		guard applicationIsTerminating == false else { return }
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
		guard applicationIsTerminating == false else { return }
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
			isAwaitingConfirmation: terminationStage == .confirming,
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
		case .overrideConfirmation:
			Self.terminationLogger.debug("Termination can no longer wait for the confirmation")
			terminationConfirmation?.cancel()
			terminationConfirmation = nil
			terminationStage = .running
			Task { [weak self] in
				self?.performApplicationTerminationStepOne()
			}
		case .begin:
			Task { [weak self] in
				self?.performApplicationTerminationStepOne()
			}
		case .confirm:
			presentTerminationConfirmation()
		}

		return .terminateLater
	}

	/** The sheet's answer reports to NSApp and begins termination itself.

	 Sheets stack, so a second ⌘Q while this one is up would queue a second
	 sheet and run both completions: two shutdowns, or a cancel answered on top
	 of one already in flight. The stage is what keeps the second request from
	 asking again.

	 The window comes forward first, because nobody can answer a sheet on a
	 window they cannot see. Quitting from the Dock with the main window closed,
	 or with the application hidden, left termination stuck behind that sheet
	 for good, and a logout stuck behind termination. */
	private func presentTerminationConfirmation() {
		terminationStage = .confirming

		NSApp.activate()
		mainWindow.makeKeyAndOrderFront(nil)

		let request = AlertRequest(
			title: PromptStrings.Application.quitTitle,
			body: PromptStrings.Application.quitBody,
			defaultButton: PromptStrings.Application.quitButtonTitle,
			alternateButton: PromptStrings.Action.cancel
		)

		terminationConfirmation = Task { [weak self] in
			let outcome = await Alerts.run(request, on: .mainWindow)
			/* A request that could not wait cancelled this task. It took the
			 sheet down and began termination itself. */
			guard Task.isCancelled == false, let self else { return }
			terminationConfirmation = nil
			terminationStage = .running

			let result = outcome.response == .default

			Self.terminationLogger.debug("Perform termination: \(result)")

			if result == false {
				NSApp.reply(toApplicationShouldTerminate: false)
				return
			}

			performApplicationTerminationStepOne()
		}
	}

	private func terminatingClientsDidFinish() {
		guard terminationStage == .disconnecting else {
			return
		}

		terminationStage = .savingLogs
		pendingLogDrains = 2

		Self.terminationLogger.debug("All clients finished; saving history and draining transcript files")

		// Do not await a blocked disk operation in a task group: cancellation cannot
		// interrupt fsync, and the group would still wait for its child to return.
		historicLogSaveTimeoutTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(terminationHistoricLogSaveTimeout))
			guard Task.isCancelled == false, let self else { return }
			Self.terminationLogger.error("Log shutdown deadline expired; pending log data may be lost")
			finishTermination()
		}

		FileLogger.prepareForApplicationTermination { [weak self] succeeded in
			guard let self else { return }
			if !succeeded {
				Self.terminationLogger.error("Transcript drain completed with file errors; some log data was not saved")
			}
			logDrainDidFinish()
		}

		LogControllerHistoricLogFile.shared
			.prepareForApplicationTermination { [weak self] in
				Task { @MainActor in
					self?.logDrainDidFinish()
				}
			}
	}

	private func logDrainDidFinish() {
		guard terminationStage == .savingLogs, pendingLogDrains > 0 else { return }
		pendingLogDrains -= 1
		guard pendingLogDrains == 0 else { return }
		finishTermination()
	}

	/// Runs step three once, whether both drains reported in or the deadline
	/// expired first.
	private func finishTermination() {
		guard terminationStage == .savingLogs else { return }
		historicLogSaveTimeoutTask?.cancel()
		historicLogSaveTimeoutTask = nil
		performApplicationTerminationStepThree()
	}

	private func performApplicationTerminationStepOne() {
		/* Nothing may run the teardown twice. A second pass re-seeds
		 `terminatingClientCount` while the first round's clients are still
		 reporting in. */
		guard applicationIsTerminating == false else {
			Self.terminationLogger.debug("Step one skipped; termination is already in progress")
			return
		}

		Self.terminationLogger.debug("Step one entry")

		terminationStage = .disconnecting

		SharedApplication.sharedAppearance().prepareForApplicationTermination()

		mainWindow.prepareForApplicationTermination()

		/* The application keeps its delegate here. Without one, AppKit answers
		 a second quit request, such as another ⌘Q, the Dock's Quit or a
		 logout, with an immediate exit. That exit came before step three saved
		 the world, unloaded the plugins and drained the logs.
		 `applicationShouldTerminate` answers the request instead and leaves
		 this shutdown alone. */

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
		 historic log has been saved and transcript files drained. With no clients,
		 assigning zero here continues immediately. */
		terminatingClientCount = world.clientCount

		world.prepareForApplicationTermination()
	}

	private func performApplicationTerminationStepThree() {
		Self.terminationLogger.debug("Step three entry")

		terminationStage = .finished

		Self.terminationLogger.debug("Saving IRC world")
		world.save()

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
	 all this path skips is the confirmation sheet. A sheet already on screen
	 comes down instead of holding termination up. */
	public func terminateGracefully() {
		skipTerminateConfirmation = true

		NSApp.terminate(nil)
	}

	// MARK: - NSWorkspace Notifications

	/// Registered with `NSAppleEventManager`, which reaches it by selector.
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

		/* Only an engine that already exists. Going to sleep is no reason to
		 start one. */
		if let speechSynthesizer = SharedApplication.existingSpeechSynthesizer() {
			speechSynthesizer.isStopped = true
			speechSynthesizer.clearQueue()
		}

		SharedApplication.sharedNetworkReachabilityNotifier().stopNotifier()
	}

	private func computerDidWakeUp(_: Notification) {
		Self.logger.log("Waking from sleep")

		SharedApplication.existingSpeechSynthesizer()?.isStopped = false
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
