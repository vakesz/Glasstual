// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

@objc(GlasstualApplication)
final class Application: NSApplication, CustomKeyboardEventResponder {
	private var applicationController: ApplicationDelegate!
	private var menuController: MenuActionController!

	override init() {
		super.init()
		/* Before AppKit reads it: `ApplePersistence` off stops saved state being
		 written as well as restored. The registration domain is not stored, so
		 this changes nothing for the person's own launches. */
		if ApplicationForeground.mode.restoresWindows == false {
			UserDefaults.standard.register(defaults: ["ApplePersistence": false])
		}

		let applicationController = ApplicationDelegate()
		let menuController = MenuActionController()
		applicationController.menuController = menuController
		delegate = applicationController
		self.applicationController = applicationController
		self.menuController = menuController
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("Application does not support decoding")
	}

	/// The funnel for every restored window. The test host and the harness
	/// restore none, so a saved window cannot come on screen in front of the
	/// person's work.
	override func restoreWindow(
		withIdentifier identifier: NSUserInterfaceItemIdentifier,
		state: NSCoder,
		completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
	) -> Bool {
		guard ApplicationForeground.mode.restoresWindows else {
			assert(ApplicationForeground.mode != .interactive, "Only a test launch suppresses restoration")
			completionHandler(nil, nil)
			return true
		}

		return super.restoreWindow(withIdentifier: identifier, state: state, completionHandler: completionHandler)
	}

	override func sendEvent(_ event: NSEvent) {
		if performedCustomKeyboardEvent(event) {
			return
		}

		super.sendEvent(event)
	}

	func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
		guard event.type == .keyDown else {
			return false
		}

		if sendCustomKeyboardEvent(event, to: keyWindow) {
			return true
		}

		if sendCustomKeyboardEvent(event, to: keyWindow?.firstResponder) {
			return true
		}

		return false
	}

	func sendCustomKeyboardEvent(_ event: NSEvent, to object: AnyObject?) -> Bool {
		guard let responder = object as? any CustomKeyboardEventResponder else {
			return false
		}

		return responder.performedCustomKeyboardEvent(event)
	}
}
