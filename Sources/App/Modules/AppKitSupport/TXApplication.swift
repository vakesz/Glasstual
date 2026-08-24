/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TXApplication)
public final class Application: NSApplication {
	@objc public class func checkForOtherCopiesOfGlasstualRunning() -> Bool {
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
				withMessage: LocalizedKey("Prompts[kx4-q8]"),
				title: LocalizedKey("Prompts[hcb-3i]"),
				defaultButton: LocalizedKey("Prompts[mvh-ms]"),
				alternateButton: LocalizedKey("Prompts[99q-gg]")
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

	@objc(performedCustomKeyboardEvent:)
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

	@objc(sendCustomKeyboardEvent:toObject:)
	public func sendCustomKeyboardEvent(_ event: NSEvent, to object: AnyObject?) -> Bool {
		guard let object else {
			return false
		}

		let selector = NSSelectorFromString("performedCustomKeyboardEvent:")

		guard object.responds(to: selector) else {
			return false
		}

		guard let method = object.method(for: selector) else {
			return false
		}

		typealias Handler = @convention(c) (AnyObject, Selector, NSEvent) -> Bool
		let handler = unsafeBitCast(method, to: Handler.self)

		return handler(object, selector, event)
	}
}
