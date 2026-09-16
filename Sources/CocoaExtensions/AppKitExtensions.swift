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
/* A portion of this source file contains copyrighted work derived from one or more
 3rd party, open source projects. The use of this work is hereby acknowledged. */

/*
 The New BSD License

 Copyright (c) 2008 - 2010 Satoshi Nakagawa < psychs AT limechat DOT net >
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.
 */

import AppKit
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
	func hasTrait(_ trait: NSFontTraitMask) -> Bool {
		NSFontManager.shared.traits(of: self).contains(trait)
	}
}

public extension NSMenuItem {
	var userInfoString: String? {
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

	func setUserInfoString(_ userInfo: String?, recursively: Bool) {
		if recursively, let submenu {
			for item in submenu.items {
				item.setUserInfoString(userInfo, recursively: true)
			}
		}

		userInfoString = userInfo
	}
}

public extension NSWindow {
	var isInactive: Bool {
		!isKeyWindow && !isMainWindow
	}

	/// Centres the window on the screen it is on. `NSScreen.main` is the
	/// screen holding the key window, which need not be this window's screen.
	func centerOnScreen() {
		guard let screen = screen ?? NSScreen.main else {
			return
		}

		let visibleFrame = screen.visibleFrame
		let centeredOrigin = NSPoint(
			x: visibleFrame.midX - frame.width / 2,
			y: visibleFrame.midY - frame.height / 2
		)
		setFrame(NSRect(origin: centeredOrigin, size: frame.size), display: true, animate: true)
	}

	var frontmostAttachedSheet: NSWindow {
		var deepestWindow = self
		while let attachedSheet = deepestWindow.attachedSheet {
			deepestWindow = attachedSheet
		}
		return deepestWindow
	}
}

@MainActor
public extension NSTextView {
	var focused: Bool {
		window?.firstResponder === self
	}

	func focus() {
		guard !focused else { return }
		window?.makeFirstResponder(self)
	}

	/// The whole of the text, in the UTF-16 units `NSTextStorage` counts in.
	var range: NSRange {
		NSRange(location: 0, length: Int(stringLength))
	}

	var stringLength: UInt {
		UInt((string as NSString).length)
	}
}

public extension NSPasteboard {
	var textualStringContent: String? {
		get { string(forType: .string) }
		set {
			declareTypes([.string], owner: nil)

			if let newValue {
				setString(newValue, forType: .string)
			} else {
				setData(nil, forType: .string)
			}
		}
	}
}
