/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
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
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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

import Foundation

@objc(TPCPreferencesUserDefaults)
public final class TextualUserDefaults: UserDefaults {
	private static let storageSuiteName: String = {
		#if DEBUG
			if let reviewSuite = ProcessInfo.processInfo.environment["GLASSTUAL_UI_REVIEW_SUITE"],
			   !reviewSuite.isEmpty
			{
				return reviewSuite
			}
		#endif

		return TXBundleBuildGroupContainerIdentifier
	}()

	private nonisolated(unsafe) static let sharedInstance =
		TextualUserDefaults(storageSuiteName: storageSuiteName)

	private init(storageSuiteName: String) {
		super.init(suiteName: storageSuiteName)!
	}

	override public convenience init?(suiteName _: String?) {
		self.init(storageSuiteName: Self.storageSuiteName)
	}

	@objc(sharedUserDefaults)
	public class func shared() -> TextualUserDefaults {
		sharedInstance
	}

	@objc(_setObject:forKey:)
	public func setObjectWithoutNotification(_ value: Any?, forKey defaultName: String) {
		super.set(value, forKey: defaultName)
	}

	override public func set(_ value: Any?, forKey defaultName: String) {
		set(value, forKey: defaultName, postNotification: true)
	}

	@objc(setObject:forKey:postNotification:)
	public func set(_ value: Any?, forKey defaultName: String, postNotification: Bool) {
		let oldValue = object(forKey: defaultName)
		if let oldValue = oldValue as? NSObject, oldValue.isEqual(value) {
			return
		}

		willChangeValue(forKey: defaultName)
		if value != nil || oldValue != nil {
			setObjectWithoutNotification(value, forKey: defaultName)
		}
		didChangeValue(forKey: defaultName)

		guard postNotification else { return }
		NotificationCenter.default.post(
			name: Notification.Name("TPCPreferencesUserDefaultsDidChangeNotification"),
			object: self,
			userInfo: ["changedKey": defaultName]
		)
	}

	override public func set(_ value: Int, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setUnsignedInteger:forKey:)
	override public func setUnsignedInteger(_ value: UInt, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setShort:forKey:)
	override public func setShort(_ value: Int16, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setUnsignedShort:forKey:)
	override public func setUnsignedShort(_ value: UInt16, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setLong:forKey:)
	override public func setLong(_ value: Int, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setUnsignedLong:forKey:)
	override public func setUnsignedLong(_ value: UInt, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setLongLong:forKey:)
	override public func setLongLong(_ value: Int64, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	@objc(setUnsignedLongLong:forKey:)
	override public func setUnsignedLongLong(_ value: UInt64, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ value: Float, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ value: Double, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ value: Bool, forKey defaultName: String) {
		set(NSNumber(value: value), forKey: defaultName)
	}

	override public func set(_ url: URL?, forKey defaultName: String) {
		set(url as Any?, forKey: defaultName)
	}

	override public func removeObject(forKey defaultName: String) {
		set(nil, forKey: defaultName)
	}

	@objc(registerDefault:forKey:)
	public func registerDefault(_ value: NSCopying, forKey defaultName: String) {
		register(defaults: [defaultName: value])
	}

	@objc public var registeredDefaults: [String: Any] {
		volatileDomain(forName: UserDefaults.registrationDomain)
	}
}

@objc(TPCPreferencesUserDefaultsController)
public final class TextualUserDefaultsController: NSUserDefaultsController {
	required init?(coder _: NSCoder) {
		super.init(defaults: TextualUserDefaults.shared(), initialValues: nil)
	}

	override public init(defaults _: UserDefaults?, initialValues _: [String: Any]?) {
		super.init(defaults: TextualUserDefaults.shared(), initialValues: nil)
	}
}
