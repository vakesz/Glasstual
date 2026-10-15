// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

@objc(GlasstualApplication)
final class Application: NSApplication, CustomKeyboardEventResponder {
	private var applicationController: ApplicationDelegate!
	private var menuController: MenuActionController!

	override init() {
		super.init()

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

	/// The funnel for every restored window. The test host restores none, so a
	/// saved window cannot come on screen in front of the person's work.
	override func restoreWindow(
		withIdentifier identifier: NSUserInterfaceItemIdentifier,
		state: NSCoder,
		completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
	) -> Bool {
		guard ApplicationForeground.mode.restoresWindows else {
			assert(ApplicationForeground.mode == .unitTestHost, "Only the test host suppresses restoration")
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
