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

extension NSFont {
	@objc(convertToItalics)
	var textual_convertToItalics: NSFont? {
		let manager = NSFontManager.shared
		let italicFont = manager.convert(self, toHaveTrait: .italicFontMask)

		guard textual_fontTraitIsSet(.italicFontMask) == false else {
			return self
		}

		let fontTransform = AffineTransform(scaleByX: pointSize, byY: pointSize)
		let shear = CGFloat(-tan(-14.0 * (Double.pi / 180)))
		let italicTransform = AffineTransform(m11: 1, m12: 0, m21: shear, m22: 1, tX: 0, tY: 0)

		var combinedTransform = fontTransform
		combinedTransform.append(italicTransform)

		return NSFont(descriptor: italicFont.fontDescriptor, textTransform: combinedTransform) ?? self
	}

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

extension NSScreen {
	private var textual_displayIdentifier: CGDirectDisplayID? {
		(deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
	}

	@objc(runningInHighResolutionMode)
	var textual_runningInHighResolutionMode: Bool {
		abs(backingScaleFactor - 1) > 0.01
	}

	@objc(screenResolutionString)
	var textual_screenResolutionString: String {
		guard
			let displayIdentifier = textual_displayIdentifier,
			let displayMode = CGDisplayCopyDisplayMode(displayIdentifier)
		else {
			return "\(Int(frame.width)) x \(Int(frame.height))"
		}

		return "\(displayMode.pixelWidth) x \(displayMode.pixelHeight)"
	}

	@objc(screenRefreshRate)
	var textual_screenRefreshRate: CGFloat {
		if maximumFramesPerSecond > 0 {
			return CGFloat(maximumFramesPerSecond)
		}

		guard
			let displayIdentifier = textual_displayIdentifier,
			let displayMode = CGDisplayCopyDisplayMode(displayIdentifier)
		else {
			return 0
		}

		return CGFloat(displayMode.refreshRate)
	}
}

extension NSMenuItem {
	@objc(userInfo)
	var textual_userInfo: String? {
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

		textual_userInfo = userInfo
	}

	@objc(menuItemWithTitle:target:action:)
	class func textual_menuItem(title: String, target: AnyObject, action: Selector) -> NSMenuItem {
		textual_menuItem(
			title: title,
			target: target,
			action: action,
			keyEquivalent: "",
			keyEquivalentMask: []
		)
	}

	@objc(menuItemWithTitle:target:action:keyEquivalent:keyEquivalentMask:)
	class func textual_menuItem(
		title: String,
		target: AnyObject,
		action: Selector,
		keyEquivalent: String,
		keyEquivalentMask: NSEvent.ModifierFlags
	) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
		item.keyEquivalentModifierMask = keyEquivalentMask
		item.target = target

		return item
	}
}

extension NSObject {
	@objc(isEqualIgnoringCase:)
	func textual_isEqualIgnoringCase(_ other: Any) -> Bool {
		if let left = self as? NSString, let right = other as? NSString {
			return left.caseInsensitiveCompare(right as String) == .orderedSame
		}
		return isEqual(other)
	}

	@objc(cancelPerformRequests)
	func textual_cancelPerformRequests() {
		NSObject.cancelPreviousPerformRequests(withTarget: self)
	}

	@objc(cancelPerformRequestsWithSelector:)
	func textual_cancelPerformRequests(with selector: Selector) {
		NSObject.cancelPreviousPerformRequests(withTarget: self, selector: selector, object: nil)
	}

	@objc(cancelPerformRequestsWithSelector:object:)
	func textual_cancelPerformRequests(with selector: Selector, object: Any?) {
		NSObject.cancelPreviousPerformRequests(withTarget: self, selector: selector, object: object)
	}

	@objc(performSelectorInCommonModes:afterDelay:)
	func textual_performSelectorInCommonModes(_ selector: Selector, afterDelay delay: TimeInterval) {
		perform(selector, with: nil, afterDelay: delay, inModes: [.common])
	}

	@objc(performSelectorInCommonModes:withObject:afterDelay:)
	func textual_performSelectorInCommonModes(
		_ selector: Selector,
		with object: Any?,
		afterDelay delay: TimeInterval
	) {
		perform(selector, with: object, afterDelay: delay, inModes: [.common])
	}
}

extension NSArrayController {
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
