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

/** An associated-object key is only an address: nothing ever reads or writes
 through it. A static string literal supplies one from the binary's constant
 data, which makes it stable, unique to this property and `Sendable` -- none of
 which a mutable global was. */
private let archivedConstraintConstantName: StaticString = "com.vakesz.glasstual.archivedConstraintConstant"

private var archivedConstraintConstantKey: UnsafeRawPointer {
	UnsafeRawPointer(archivedConstraintConstantName.utf8Start)
}

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
	func textual_decodeDictionary(forKey key: String) -> NSDictionary? {
		decodeObject(of: NSDictionary.self, forKey: key)
	}

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
	var textualIntegerStringValueWithLeadingZero: String {
		int64Value.formatted(.number.precision(.integerLength(2...)).grouping(.never))
	}
}

public extension NSWorkspace {
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
	var textualDisplayName: String? {
		object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
	}

	class func textual_formattedDisplayNames(for bundles: [Bundle]) -> String {
		bundles.compactMap(\.textualDisplayName).joined(separator: ", ")
	}

	class func textual_openInstallationLocations(for bundles: [Bundle]) {
		let locations = Set(bundles.map { $0.bundleURL.deletingLastPathComponent() })

		for location in locations {
			NSWorkspace.shared.open(location)
		}
	}
}

public extension NSLayoutConstraint {
	private var textualArchivedConstantNumber: NSNumber? {
		objc_getAssociatedObject(self, archivedConstraintConstantKey) as? NSNumber
	}

	var textualArchivedConstant: CGFloat {
		get { textualArchivedConstantNumber.map { CGFloat(truncating: $0) } ?? 0 }
		set {
			objc_setAssociatedObject(
				self,
				archivedConstraintConstantKey,
				NSNumber(value: Double(newValue)),
				.OBJC_ASSOCIATION_COPY
			)
		}
	}

	func textual_archiveConstant() {
		textualArchivedConstant = constant
	}

	func textual_restoreArchivedConstant() {
		guard let archivedConstant = textualArchivedConstantNumber else {
			return
		}

		constant = CGFloat(truncating: archivedConstant)
	}

	func textual_zeroOutConstant() {
		constant = 0
	}
}
