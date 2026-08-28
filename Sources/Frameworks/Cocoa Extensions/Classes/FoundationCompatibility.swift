/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2018 Codeux Software, LLC
 *         Copyright (c) 2017, 2018 Codeux Software, LLC
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

/// `CharacterSet` is a `Sendable` value type, so these need no isolation
/// annotation and no `NSCharacterSet` bridging at the point of use.
public extension CharacterSet {
	static let textualHexadecimal = CharacterSet(charactersIn: "abcdefABCDEF0123456789")

	static let textualPercentEncoded = CharacterSet(
		charactersIn: "-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"
	)

	static let textualAlphanumericDashPeriod = CharacterSet(
		charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
	)

	static let textualLetter = CharacterSet(
		charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	)
}

public extension NSCoder {
	@objc(decodeDictionaryForKey:)
	func textual_decodeDictionary(forKey key: String) -> NSDictionary? {
		decodeObject(of: NSDictionary.self, forKey: key)
	}

	@objc(decodeStringForKey:)
	func textual_decodeString(forKey key: String) -> NSString? {
		decodeObject(of: NSString.self, forKey: key)
	}
}

public extension Int64 {
	/// A file-style byte count with a zero-padded fraction, e.g. "1.20 MB".
	var textualPaddedByteCountDescription: String {
		formatted(.byteCount(style: .file))
	}
}

public extension NSNumber {
	@objc(integerStringValueWithLeadingZero)
	var textualIntegerStringValueWithLeadingZero: String {
		int64Value.formatted(.number.precision(.integerLength(2...)).grouping(.never))
	}
}

public extension NSWorkspace {
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

public extension Bundle {
	@objc(displayName)
	var textualDisplayName: String? {
		object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
	}

	@objc(formattedDisplayNamesForBundles:)
	class func textual_formattedDisplayNames(for bundles: [Bundle]) -> String {
		bundles.compactMap(\.textualDisplayName).joined(separator: ", ")
	}

	@objc(openInstallationLocationsForBundles:)
	class func textual_openInstallationLocations(for bundles: [Bundle]) {
		let locations = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })

		for location in locations {
			NSWorkspace.shared.open(location)
		}
	}
}

public extension NSLayoutConstraint {
	private var textualArchivedConstantNumber: NSNumber? {
		objc_getAssociatedObject(self, &archivedConstraintConstantKey) as? NSNumber
	}

	@objc(archivedConstant)
	var textualArchivedConstant: CGFloat {
		get { textualArchivedConstantNumber.map { CGFloat(truncating: $0) } ?? 0 }
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
		textualArchivedConstant = constant
	}

	@objc(restoreArchivedConstant)
	func textual_restoreArchivedConstant() {
		guard let archivedConstant = textualArchivedConstantNumber else {
			return
		}

		constant = CGFloat(truncating: archivedConstant)
	}

	@objc(zeroOutConstant)
	func textual_zeroOutConstant() {
		constant = 0
	}
}
