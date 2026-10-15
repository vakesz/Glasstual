// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** Whether this process is the application a person launched, or the host
 `make test` launches to load the unit-test bundle.

 The unit tests run inside a full launch of Glasstual.app. That launch used to
 activate the application, raise the main window and the welcome window, and
 take the person's focus on every run. The test host does everything else a
 launch does, but stays in the background with its windows off screen. The
 smoke and end-to-end runs drive the real application through Accessibility,
 so they launch without the variable and keep the interactive behaviour. */
enum ApplicationLaunchMode: Equatable {
	case interactive
	case unitTestHost

	/// Set by the Glasstual scheme's test action in `project.yml`. Read in
	/// Debug builds only; a Release build is always interactive.
	static let unitTestHostVariable = "GLASSTUAL_UNIT_TEST_HOST"

	static let current = Self(environment: ProcessInfo.processInfo.environment)

	init(environment: [String: String]) {
		#if DEBUG
			let value = environment[Self.unitTestHostVariable] ?? ""
			self = value.isEmpty ? .interactive : .unitTestHost
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
		case .interactive: nil
		case .unitTestHost: .prohibited
		}
	}

	/// Whether the application may activate itself and raise its windows.
	var takesForeground: Bool {
		self == .interactive
	}

	/// Whether AppKit may restore saved windows. The test host shares the
	/// application's container, so it would otherwise reopen the person's
	/// windows and record its own over them.
	var restoresWindows: Bool {
		self == .interactive
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
