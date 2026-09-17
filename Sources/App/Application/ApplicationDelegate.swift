// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Network
import os

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

/// What a network path update means for the clients that watch it.
enum ReachabilityPathEvent {
	/// Nothing to report: the first path, or one that repeats the last.
	case none
	case becameReachable
	case becameUnreachable
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "General"
	)

	static let terminationLogger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Termination"
	)

	private var hasInstalledMainWindow = false

	private(set) var ghostModeIsOn = false
	private(set) var applicationIsLaunched = false

	/// Shutdown has begun; accepted Settings saves finish before teardown.
	var applicationIsTerminating: Bool {
		terminationStage >= .finishingSettings
	}

	/* The shutdown sequence itself is in ApplicationTermination.swift. Stored
	 properties cannot live in an extension, so its state is declared here and
	 nothing else reads it. */

	var terminationStage: ApplicationTerminationStage = .running
	/// The two log drains still running. Step three waits for both, or for the
	/// deadline, whichever comes first.
	var pendingLogDrains = 0
	/// Bounds both scrollback persistence and the independent transcript-file drain.
	var scrollbackSaveDeadline: ClientTimer?
	var skipTerminateConfirmation = false
	/// The quit confirmation while it is on screen. Cancelling it takes the
	/// sheet down without its answer being acted on.
	var terminationConfirmation: Task<Void, Never>?
	var settingsTerminationTask: Task<Void, Never>?
	var credentialTerminationTask: Task<Void, Never>?

	private var reachabilityTask: Task<Void, Never>?
	private var isNetworkReachable = false
	/** Seeded once per process rather than per monitor. The monitor is stopped on
	 sleep and started again on wake, and resetting the seed there made every
	 restart discard its first update, so a connectivity change across the sleep
	 was never reported. */
	private var receivedInitialPath = false

	let notifications = NotificationSubscriptions()
	private lazy var resourceFileImporter = ResourceFileImporter()

	/// IUO preserves the established launch-time contract while allowing nil in tests.
	var mainWindow: MainWindow!
	weak var menuController: MenuActionController?
	var clientDirectory: ClientDirectory!

	var terminatingClientCount: UInt = 0 {
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

	override init() {
		super.init()

		AppServices.setDelegate(self)
		prepareInitialState()
	}

	private func prepareInitialState() {
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

		PreferenceRegistration.prepareForLaunch()

		_ = AppServices.appearance

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

	func applicationWakeStepOne() {
		clientDirectory = ClientDirectory()
	}

	/** Hands the IRC layer the window, the menus and this controller, and makes
	 both of the first two observers of the client directory. Everything the connection code
	 used to reach for through `AppServices.delegate` arrives this way. */
	func installClientServices() {
		let services = ClientEnvironment.shared.services
		services.output = mainWindow
		services.menu = menuController
		services.channelList = AppServices.scenes
		services.applicationState = self
		services.clientDirectory = clientDirectory

		if let mainWindow {
			clientDirectory?.addObserver(mainWindow)
		}

		if let menuController {
			clientDirectory?.addObserver(menuController)
		}
	}

	func applicationWakeStepTwo() {
		SystemInformation.beginObservingSleepState()

		startWatchingNetworkPath()

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
			await BundleResources.copyResourcesToApplicationSupportFolder()
		}

		// The script scan reads directories, so it runs off the main actor and
		// lands whenever it lands; nothing at launch waits for it.
		AppServices.scripts.refreshCommands()
		completeApplicationLaunch()
	}

	// MARK: - Network reachability

	/** Watches the default network path and tells the clients when it comes and
	 goes. `ClientDirectory` lives on the main actor, so the loop does too: no
	 lock, no queue hop, no opting out of the checker. */
	private func startWatchingNetworkPath() {
		/* A path monitor is single use: once cancelled it never delivers another
		 update. Create a fresh one for every start. */
		reachabilityTask?.cancel()

		reachabilityTask = Task { @MainActor [weak self] in
			for await path in NWPathMonitor() {
				guard let self else { return }

				let event = Self.evaluatePathChange(
					reachable: path.status == .satisfied,
					currentlyReachable: &isNetworkReachable,
					receivedInitialPath: &receivedInitialPath
				)

				switch event {
				case .none: break
				case .becameReachable: clientDirectory?.noteReachabilityChanged(true)
				case .becameUnreachable: clientDirectory?.noteReachabilityChanged(false)
				}
			}
		}
	}

	func stopWatchingNetworkPath() {
		reachabilityTask?.cancel()
		reachabilityTask = nil
	}

	/// What one path update means, given what the last one said.
	nonisolated static func evaluatePathChange( // nonisolated: pure
		reachable: Bool,
		currentlyReachable: inout Bool,
		receivedInitialPath: inout Bool
	) -> ReachabilityPathEvent {
		let wasReachable = currentlyReachable

		currentlyReachable = reachable

		/* The first path update describes the state at launch rather than a
		 change. Seed from it without reporting one. */
		if receivedInitialPath == false {
			receivedInitialPath = true

			return .none
		}

		if reachable == wasReachable {
			return .none
		}

		return reachable ? .becameReachable : .becameUnreachable
	}

	// MARK: - NSApplication Delegate

	func applicationWillFinishLaunching(_: Notification) {
		/* A second copy used to be met with a modal warning that the
		 preferences "may become corrupted". `LSMultipleInstancesProhibited`
		 means there is never a second copy to warn about: Launch Services
		 activates the one that is already running. */
		AppServices.scenes.install(in: NSApp)

		/* UserNotifications.framework wants delegation set before app has
		 finished launching. A simple access to the singleton will set this
		 for us which we can just do here. */
		_ = AppServices.notifications

		installMainWindow()
	}

	func applicationDidFinishLaunching(_: Notification) {
		mainWindow.makeMain()
		mainWindow.makeKeyAndOrderFront(nil)
		presentOnboardingIfNeeded()
	}

	private func completeApplicationLaunch() {
		applicationIsLaunched = true

		if mainWindow.reloadLoadingScreen() {
			clientDirectory.autoConnect(afterWakeup: false)
		}
	}

	/** First launch: no client has been configured and the setup flow has not
	 been completed or skipped before. The flow is shown on top of the main
	 window's "add a server" placeholder. */
	private func presentOnboardingIfNeeded() {
		guard OnboardingModel.shouldPresentOnLaunch() else {
			return
		}

		AppServices.scenes.openOnboarding()
	}

	/* The delegate stays attached until the process exits. The callbacks below
	 can therefore arrive during termination, and they must not start work that
	 teardown is already undoing. */

	func applicationDidBecomeActive(_: Notification) {
		guard applicationIsTerminating == false else { return }
		AppServices.scripts.refreshCommands()
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		if applicationIsTerminating {
			return false
		}

		mainWindow.makeKeyAndOrderFront(nil)
		return true
	}

	/** Scripts the user opened from the Finder. The declared
	 document types used to name an `NSDocument` subclass, whose nonisolated
	 `read(from:ofType:)` had to assume the main actor before it could put an
	 alert on screen; this delegate method is isolated by declaration. */
	func application(_: NSApplication, open urls: [URL]) {
		guard applicationIsTerminating == false else { return }
		resourceFileImporter.open(urls)
	}

	func applicationDockMenu(_: NSApplication) -> NSMenu? {
		menuController?.dockMenu
	}

	func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
		/* The main window encodes its selection with secure coding. */
		true
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
		clientDirectory.prepareForScreenSleep()
	}

	private func computerScreenDidWake(_: Notification) {
		Self.logger.log("Waking from screen sleep")
		clientDirectory.wakeFromScreenSleep()
	}

	private func computerWillSleep() {
		Self.logger.log("Preparing for sleep")

		clientDirectory.prepareForSleep()

		stopWatchingNetworkPath()
	}

	private func computerDidWakeUp(_: Notification) {
		Self.logger.log("Waking from sleep")

		startWatchingNetworkPath()

		clientDirectory.autoConnect(afterWakeup: true)
	}

	private func computerWillPowerOff() {
		terminateGracefully()
	}
}
