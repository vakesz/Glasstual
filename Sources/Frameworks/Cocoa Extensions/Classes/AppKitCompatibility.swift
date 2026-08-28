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

private nonisolated(unsafe) var menuItemUserInfoKey: UInt8 = 0

public extension NSFont {
	@objc(fontTraitSet:)
	func textual_fontTraitIsSet(_ trait: NSFontTraitMask) -> Bool {
		NSFontManager.shared.traits(of: self).contains(trait)
	}

	@objc(fontIsAvailable:)
	class func textual_fontIsAvailable(_ fontName: String) -> Bool {
		if NSFont(name: fontName, size: 9) != nil {
			return true
		}

		return NSFontManager.shared.availableFonts.contains {
			$0.compare(fontName, options: .caseInsensitive) == .orderedSame
		}
	}
}

public extension NSScreen {
	private var textualDisplayIdentifier: CGDirectDisplayID? {
		(deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
	}

	@objc(screenResolutionString)
	var textualScreenResolutionString: String {
		guard
			let displayIdentifier = textualDisplayIdentifier,
			let displayMode = CGDisplayCopyDisplayMode(displayIdentifier)
		else {
			return "\(Int(frame.width)) x \(Int(frame.height))"
		}

		return "\(displayMode.pixelWidth) x \(displayMode.pixelHeight)"
	}

	@objc(screenRefreshRate)
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
	@objc(userInfo)
	var textualUserInfo: String? {
		get { objc_getAssociatedObject(self, &menuItemUserInfoKey) as? String }
		set {
			objc_setAssociatedObject(
				self,
				&menuItemUserInfoKey,
				newValue,
				.OBJC_ASSOCIATION_COPY_NONATOMIC
			)
		}
	}

	@objc(setUserInfo:recursively:)
	func textual_setUserInfo(_ userInfo: String?, recursively: Bool) {
		if recursively, let submenu {
			for item in submenu.items {
				item.textual_setUserInfo(userInfo, recursively: true)
			}
		}

		textualUserInfo = userInfo
	}
}

/** These are Swift extension members, not Objective-C categories: an @objc
 method on NSObject installs an unprefixed selector on every class in the
 process and can collide with a current or future Apple implementation. */
public extension NSObject {
	func textual_isEqualIgnoringCase(_ other: Any) -> Bool {
		if let left = self as? NSString, let right = other as? NSString {
			return left.caseInsensitiveCompare(right as String) == .orderedSame
		}
		return isEqual(other)
	}

	func textual_cancelPerformRequests() {
		NSObject.cancelPreviousPerformRequests(withTarget: self)
	}

	func textual_performSelectorInCommonModes(_ selector: Selector, afterDelay delay: TimeInterval) {
		perform(selector, with: nil, afterDelay: delay, inModes: [.common])
	}

	func textual_performSelectorInCommonModes(
		_ selector: Selector,
		with object: Any?,
		afterDelay delay: TimeInterval
	) {
		perform(selector, with: object, afterDelay: delay, inModes: [.common])
	}
}

public extension NSArrayController {
	@objc(removeAllArrangedObjects)
	func textual_removeAllArrangedObjects() {
		let count = (arrangedObjects as? [Any])?.count ?? 0
		remove(atArrangedObjectIndexes: IndexSet(integersIn: 0 ..< count))
	}

	@objc(replaceObjectAtArrangedObjectIndex:withObject:)
	func textual_replaceObject(atArrangedObjectIndex index: UInt, with object: Any) {
		insert(object, atArrangedObjectIndex: Int(index) + 1)
		remove(atArrangedObjectIndex: Int(index))
	}

	@objc(moveObjectAtArrangedObjectIndex:toIndex:)
	func textual_moveObject(atArrangedObjectIndex sourceIndex: UInt, to destinationIndex: UInt) {
		guard let objects = arrangedObjects as? [Any] else {
			return
		}

		let object = objects[Int(sourceIndex)]
		remove(atArrangedObjectIndex: Int(sourceIndex))

		let insertionIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
		insert(object, atArrangedObjectIndex: Int(insertionIndex))
	}
}
