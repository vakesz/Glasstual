/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
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
import CoreFoundation
import ObjectiveC

private nonisolated(unsafe) var archivedConstraintConstantKey: UInt8 = 0
private nonisolated(unsafe) let hexadecimalCharacterSet = NSCharacterSet(
	charactersIn: "abcdefABCDEF0123456789"
)
private nonisolated(unsafe) let percentEncodedCharacterSet = NSCharacterSet(
	charactersIn: "-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"
)
private nonisolated(unsafe) let alphanumericUnderscoreCharacterSet = NSCharacterSet(
	charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
)
private nonisolated(unsafe) let alphanumericUnderscoreDashCharacterSet = NSCharacterSet(
	charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
)
private nonisolated(unsafe) let alphanumericUnderscoreDashSlashCharacterSet = NSCharacterSet(
	charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-/"
)
private nonisolated(unsafe) let alphanumericUnderscoreDashPeriodCharacterSet = NSCharacterSet(
	charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
)
private nonisolated(unsafe) let letterCharacterSet = NSCharacterSet(
	charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
)
private nonisolated(unsafe) let decimalCharacterSet = NSCharacterSet(charactersIn: "0123456789.")

extension NSCharacterSet {
	@objc(hexadecimalCharacterSet)
	class var textual_hexadecimalCharacterSet: NSCharacterSet {
		hexadecimalCharacterSet
	}

	@objc(percentEncodedCharacterSet)
	class var textual_percentEncodedCharacterSet: NSCharacterSet {
		percentEncodedCharacterSet
	}

	@objc(Ato9Underscore)
	class var textual_alphanumericUnderscoreCharacterSet: NSCharacterSet {
		alphanumericUnderscoreCharacterSet
	}

	@objc(Ato9UnderscoreDash)
	class var textual_alphanumericUnderscoreDashCharacterSet: NSCharacterSet {
		alphanumericUnderscoreDashCharacterSet
	}

	@objc(Ato9UnderscoreDashForwardSlash)
	class var textual_alphanumericUnderscoreDashSlashCharacterSet: NSCharacterSet {
		alphanumericUnderscoreDashSlashCharacterSet
	}

	@objc(Ato9UnderscoreDashPeriod)
	class var textual_alphanumericUnderscoreDashPeriodCharacterSet: NSCharacterSet {
		alphanumericUnderscoreDashPeriodCharacterSet
	}

	@objc(AtoZCharacterSet)
	class var textual_letterCharacterSet: NSCharacterSet {
		letterCharacterSet
	}

	@objc(ZeroToNineDecimalCharacterSet)
	class var textual_decimalCharacterSet: NSCharacterSet {
		decimalCharacterSet
	}
}

extension NSCoder {
	@objc(decodeDictionaryForKey:)
	func textual_decodeDictionary(forKey key: String) -> NSDictionary? {
		decodeObject(of: NSDictionary.self, forKey: key)
	}

	@objc(decodeDataForKey:)
	func textual_decodeData(forKey key: String) -> NSData? {
		decodeObject(of: NSData.self, forKey: key)
	}

	@objc(decodeStringForKey:)
	func textual_decodeString(forKey key: String) -> NSString? {
		decodeObject(of: NSString.self, forKey: key)
	}

	@objc(decodeUnsignedIntegerForKey:)
	func textual_decodeUnsignedInteger(forKey key: String) -> UInt {
		decodeObject(of: NSNumber.self, forKey: key)?.uintValue ?? 0
	}

	@objc(decodeUnsignedShortForKey:)
	func textual_decodeUnsignedShort(forKey key: String) -> UInt16 {
		decodeObject(of: NSNumber.self, forKey: key)?.uint16Value ?? 0
	}

	@objc(encodeData:forKey:)
	func textual_encodeData(_ value: Data, forKey key: String) {
		encode(value as NSData, forKey: key)
	}

	@objc(encodeString:forKey:)
	func textual_encodeString(_ value: String, forKey key: String) {
		encode(value as NSString, forKey: key)
	}

	@objc(encodeUnsignedInteger:forKey:)
	func textual_encodeUnsignedInteger(_ value: UInt, forKey key: String) {
		encode(NSNumber(value: value), forKey: key)
	}

	@objc(encodeUnsignedShort:forKey:)
	func textual_encodeUnsignedShort(_ value: UInt16, forKey key: String) {
		encode(NSNumber(value: value), forKey: key)
	}

	@objc(maybeEncodeObject:forKey:)
	func textual_maybeEncodeObject(_ value: Any?, forKey key: String) {
		guard let value else {
			return
		}

		encode(value, forKey: key)
	}
}

extension NSTabView {
	@objc(indexOfSelectedItem)
	var textual_indexOfSelectedItem: UInt {
		guard let selectedTabViewItem else {
			return UInt.max
		}

		return UInt(indexOfTabViewItem(selectedTabViewItem))
	}
}

extension ByteCountFormatter {
	@objc(stringFromByteCountWithPaddedDigits:)
	class func textual_stringFromByteCountWithPaddedDigits(_ byteCount: Int64) -> String? {
		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true

		return formatter.string(fromByteCount: byteCount)
	}
}

extension NSError {
	private func textual_isError(inDomain domain: String, code: Int) -> Bool {
		self.domain == domain && self.code == code
	}

	@objc(isURLSessionCancelError)
	var textual_isURLSessionCancelError: Bool {
		textual_isError(inDomain: NSURLErrorDomain, code: NSURLErrorCancelled)
	}
}

extension NSNumber {
	@objc(isBooleanValue)
	var textual_isBooleanValue: Bool {
		CFGetTypeID(self) == CFBooleanGetTypeID()
	}

	@objc(integerStringValueWithLeadingZero)
	var textual_integerStringValueWithLeadingZero: String {
		String(format: "%02lld", int64Value)
	}
}

extension NSDate {
	@objc(timeIntervalSince1970)
	class func textual_timeIntervalSince1970() -> TimeInterval {
		Date().timeIntervalSince1970
	}

	@objc(timeIntervalSinceNow:)
	class func textual_timeIntervalSinceNow(_ intervalSince1970: TimeInterval) -> TimeInterval {
		textual_timeIntervalSince1970() - intervalSince1970
	}

	@objc(isInSameDayAsDate:)
	func textual_isInSameDay(as otherDate: Date) -> Bool {
		Calendar.current.isDate(self as Date, inSameDayAs: otherDate)
	}
}

extension NSWorkspace {
	@objc(nameOfApplicationToOpenURL:)
	func textual_nameOfApplication(toOpen url: URL) -> String? {
		guard
			let applicationURL = urlForApplication(toOpen: url),
			let applicationBundle = Bundle(url: applicationURL)
		else {
			return nil
		}

		return applicationBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? applicationBundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
	}
}

extension Bundle {
	@objc(displayName)
	var textual_displayName: String? {
		object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
	}

	@objc(formattedDisplayNamesForBundles:)
	class func textual_formattedDisplayNames(for bundles: [Bundle]) -> String {
		bundles.compactMap(\.textual_displayName).joined(separator: ", ")
	}

	@objc(openInstallationLocationsForBundles:)
	class func textual_openInstallationLocations(for bundles: [Bundle]) {
		let locations = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })

		for location in locations {
			NSWorkspace.shared.open(location)
		}
	}
}

extension NSLayoutConstraint {
	private var textual_archivedConstantNumber: NSNumber? {
		objc_getAssociatedObject(self, &archivedConstraintConstantKey) as? NSNumber
	}

	@objc(archivedConstant)
	var textual_archivedConstant: CGFloat {
		get { textual_archivedConstantNumber.map { CGFloat(truncating: $0) } ?? 0 }
		set {
			objc_setAssociatedObject(
				self,
				&archivedConstraintConstantKey,
				NSNumber(value: Double(newValue)),
				.OBJC_ASSOCIATION_COPY
			)
		}
	}

	@objc(archiveConstant)
	func textual_archiveConstant() {
		textual_archivedConstant = constant
	}

	@objc(restoreArchivedConstant)
	func textual_restoreArchivedConstant() {
		guard let archivedConstant = textual_archivedConstantNumber else {
			return
		}

		constant = CGFloat(truncating: archivedConstant)
	}

	@objc(zeroOutConstant)
	func textual_zeroOutConstant() {
		constant = 0
	}
}

extension NSIndexSet {
	@objc(subsetWithMaximumIndexes:)
	func textual_subset(withMaximumIndexes maximumNumberOfIndexes: UInt) -> NSIndexSet {
		precondition(maximumNumberOfIndexes > 0)

		let limitedIndexes = NSMutableIndexSet()
		var remaining = maximumNumberOfIndexes

		enumerate { index, stop in
			limitedIndexes.add(index)
			remaining -= 1
			stop.pointee = ObjCBool(remaining == 0)
		}

		return limitedIndexes.copy() as! NSIndexSet
	}
}
