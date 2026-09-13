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
import CoreGraphics
import ObjectiveC

/** The address an associated object is keyed on. It was a mutable global
 `UInt8` whose address was taken, which needed an escape hatch to be a global at
 all. A static string literal lives in the binary's constant data, so its bytes
 have exactly the property a key needs — a unique, stable address — and the
 literal itself is a value. */
private let menuItemUserInfoKeyToken: StaticString = "com.vakesz.glasstual.menuItemUserInfo"

private var menuItemUserInfoKey: UnsafeRawPointer {
	UnsafeRawPointer(menuItemUserInfoKeyToken.utf8Start)
}

public extension NSFont {
	func textual_fontTraitIsSet(_ trait: NSFontTraitMask) -> Bool {
		NSFontManager.shared.traits(of: self).contains(trait)
	}
}

public extension NSScreen {
	private var textualDisplayIdentifier: CGDirectDisplayID? {
		(deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
	}

	var textualScreenResolutionString: String {
		guard
			let displayIdentifier = textualDisplayIdentifier,
			let displayMode = CGDisplayCopyDisplayMode(displayIdentifier)
		else {
			return "\(Int(frame.width)) x \(Int(frame.height))"
		}

		return "\(displayMode.pixelWidth) x \(displayMode.pixelHeight)"
	}

	var textualScreenRefreshRate: CGFloat {
		if maximumFramesPerSecond > 0 {
			return CGFloat(maximumFramesPerSecond)
		}

		guard
			let displayIdentifier = textualDisplayIdentifier,
			let displayMode = CGDisplayCopyDisplayMode(displayIdentifier)
		else {
			return 0
		}

		return CGFloat(displayMode.refreshRate)
	}
}

public extension NSMenuItem {
	var textualUserInfo: String? {
		get { objc_getAssociatedObject(self, menuItemUserInfoKey) as? String }
		set {
			objc_setAssociatedObject(
				self,
				menuItemUserInfoKey,
				newValue,
				.OBJC_ASSOCIATION_COPY_NONATOMIC
			)
		}
	}

	func textual_setUserInfo(_ userInfo: String?, recursively: Bool) {
		if recursively, let submenu {
			for item in submenu.items {
				item.textual_setUserInfo(userInfo, recursively: true)
			}
		}

		textualUserInfo = userInfo
	}
}
