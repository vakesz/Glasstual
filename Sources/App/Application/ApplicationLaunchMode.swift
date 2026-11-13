// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** Whether this process is the application a person launched, or the host
 `make test` launches to load the unit-test bundle.

 The unit tests run inside a full launch of Glasstual.app. That launch used to
 activate the application, raise the main window and the welcome window, and
 take the person's focus on every run. The test host does everything else a
 launch does, but stays in the background with its windows off screen.

 The end-to-end harness drives the real application through Accessibility, so
 its launch is interactive, but it neither restores nor saves window state:
 the run shares the application's container with the person's own copy. */
enum ApplicationLaunchMode: Equatable {
	case interactive
	case unitTestHost
	/// A launch by `Tests/E2EHarness`. `keepsRunState` is set for a launch the
	/// harness relaunches against the same run; otherwise the application
	/// removes the run's settings, files and secrets as it quits.
	case endToEnd(keepsRunState: Bool)

	/// Set by the Glasstual scheme's test action in `project.yml`. Read in
	/// Debug builds only; a Release build is always interactive.
	static let unitTestHostVariable = "GLASSTUAL_UNIT_TEST_HOST"

	/// Set by the end-to-end harness: `1`, or `keep` for a launch whose state
	/// the next launch of the same run reads. Debug builds only.
	static let endToEndVariable = "GLASSTUAL_E2E"

	static let current = Self(environment: ProcessInfo.processInfo.environment)

	init(environment: [String: String]) {
		#if DEBUG
			if (environment[Self.unitTestHostVariable] ?? "").isEmpty == false {
				self = .unitTestHost
				return
			}
			switch environment[Self.endToEndVariable] ?? "" {
			case "": self = .interactive
			case "keep": self = .endToEnd(keepsRunState: true)
			default: self = .endToEnd(keepsRunState: false)
			}
		#else
			self = .interactive
		#endif
	}

	/** The policy applied before launch finishes, or nil to keep the bundle's.

	 A prohibited application cannot be activated, so the launch that Xcode's
	 test runner requests never brings it forward. Its windows still lay out,
	 keep first responders and take part in menu validation. */
	var activationPolicy: NSApplication.ActivationPolicy? {
		switch self {
		case .interactive, .endToEnd: nil
		case .unitTestHost: .prohibited
		}
	}

	/// Whether the application may activate itself and raise its windows.
	var takesForeground: Bool {
		self != .unitTestHost
	}

	/// Whether AppKit may restore and save window state. The test host and
	/// the harness share the application's container, so they would otherwise
	/// reopen the person's windows and record their own over them.
	var restoresWindows: Bool {
		self == .interactive
	}

	/// Whether the application may open a URL or a file in another
	/// application, reveal one in the Finder or open the Help viewer. The test
	/// host and the harness run on a person's own login while they work.
	var handsOffToSystem: Bool {
		self == .interactive
	}

	/// Whether quitting removes the run's settings suite, files and secrets.
	var removesRunStateOnQuit: Bool {
		self == .endToEnd(keepsRunState: false)
	}
}

/** The one owner of the application coming forward.

 Every activation and every raised window goes through here, so the test host
 never takes the person's focus. Ordering a window without raising it, and
 attaching a sheet, stay with their callers. */
enum ApplicationForeground {
	static let mode = ApplicationLaunchMode.current

	/// Applies the launch mode's activation policy. Call before launch finishes.
	static func prepareForLaunch(_ application: NSApplication) {
		if let policy = mode.activationPolicy {
			application.setActivationPolicy(policy)
		}
	}

	static func activate() {
		guard mode.takesForeground else { return }
		NSApp.activate()
	}

	/// Makes `window` key and orders it in front of the application's others.
	static func raise(_ window: NSWindow, sender: Any? = nil) {
		guard mode.takesForeground else { return }
		window.makeKeyAndOrderFront(sender)
	}

	/// Activates the application, then raises `window` in front of other
	/// applications' windows.
	static func bringForward(_ window: NSWindow) {
		activate()
		raise(window)
	}
}
