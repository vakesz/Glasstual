/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TVCErrorMessagePopoverController)
public final class ErrorMessagePopoverController: NSObject {
	private var visiblePopover: TVCErrorMessagePopover?

	private nonisolated(unsafe) static var sharedInstance = ErrorMessagePopoverController()

	@objc public class func sharedController() -> ErrorMessagePopoverController {
		sharedInstance
	}

	@objc(showMessage:forView:)
	public func showMessage(_ message: String, for view: NSView) {
		var popover = visiblePopover
		let popoverIsSame =
			popover != nil && popover?.view === view && popover?.message == message

		if popoverIsSame == false {
			if let popover {
				popover.close()
			}

			popover = TVCErrorMessagePopover(message: message, relativeTo: view)
		}

		if let popover {
			popover.showRelative(to: view.bounds)
		}

		if popoverIsSame == false {
			visiblePopover = popover
		}
	}

	@objc public func closeMessage() {
		closePopover(for: nil)
	}

	@objc(closeMessageForView:)
	public func closeMessage(for view: NSView) {
		closePopover(for: view)
	}

	private func closePopover(for view: NSView?) {
		guard let popover = visiblePopover else {
			return
		}

		/* popover.view is weak. When the anchoring field is being deallocated
		 the reference is already nil; the popover must still be closed. */
		if let view, let popoverView = popover.view, view !== popoverView {
			return
		}

		popover.close()
		visiblePopover = nil
	}
}
