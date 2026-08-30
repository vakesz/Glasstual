/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// Handles a key-down event before AppKit's own dispatch gets it. The key
/// window and its first responder are each offered the event in turn.
@MainActor
public protocol CustomKeyboardEventResponder: AnyObject {
	func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool
}

@objc(TXApplication)
public final class Application: NSApplication, CustomKeyboardEventResponder {
	public static func shouldContinueLaunching() -> Bool {
		let ourProcessIdentifier = ProcessInfo.processInfo.processIdentifier

		guard let ourIdentifier = Bundle.main.bundleIdentifier else {
			return true
		}

		for application in NSWorkspace.shared.runningApplications {
			guard application.bundleIdentifier == ourIdentifier else {
				continue
			}

			if application.processIdentifier == ourProcessIdentifier {
				continue
			}

			return TDCAlert.modalAlert(
				withMessage: PromptStrings.Application.continueWithAnotherInstanceBody,
				title: PromptStrings.Application.continueWithAnotherInstanceTitle,
				defaultButton: PromptStrings.Action.yes,
				alternateButton: PromptStrings.Action.no
			)
		}

		return true
	}

	override public func sendEvent(_ event: NSEvent) {
		if performedCustomKeyboardEvent(event) {
			return
		}

		super.sendEvent(event)
	}

	public func performedCustomKeyboardEvent(_ event: NSEvent) -> Bool {
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

	public func sendCustomKeyboardEvent(_ event: NSEvent, to object: AnyObject?) -> Bool {
		guard let responder = object as? any CustomKeyboardEventResponder else {
			return false
		}

		return responder.performedCustomKeyboardEvent(event)
	}
}
