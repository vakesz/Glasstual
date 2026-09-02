/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit

public extension NSWindow {
	var ceIsOccluded: Bool {
		!occlusionState.contains(.visible)
	}

	var ceIsInactive: Bool {
		!isKeyWindow && !isMainWindow
	}

	func ce_exactlyCenter() {
		guard let screen = NSScreen.main else {
			return
		}

		let visibleFrame = screen.visibleFrame
		let centeredOrigin = NSPoint(
			x: visibleFrame.midX - frame.width / 2,
			y: visibleFrame.midY - frame.height / 2
		)
		setFrame(NSRect(origin: centeredOrigin, size: frame.size), display: true, animate: true)
	}

	var ceIsBeneathMouse: Bool {
		Self.ceWindowBeneathMouse === self
	}

	var ceIsInFullscreenMode: Bool {
		styleMask.contains(.fullScreen)
	}

	var ceDeepestWindow: NSWindow {
		var deepestWindow = self
		while let attachedSheet = deepestWindow.attachedSheet {
			deepestWindow = attachedSheet
		}
		return deepestWindow
	}

	var ceTitlebarFrame: NSRect {
		guard let contentView else {
			return .zero
		}

		var titlebarFrame = frame
		titlebarFrame.origin.y += contentView.frame.height
		titlebarFrame.size.height -= contentView.frame.height
		return titlebarFrame
	}

	private static var ceWindowBeneathMouse: NSWindow? {
		let mouseLocation = NSEvent.mouseLocation
		return NSApp.orderedWindows.first { window in
			NSMouseInRect(mouseLocation, window.frame, false)
		}
	}
}
