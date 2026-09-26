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
