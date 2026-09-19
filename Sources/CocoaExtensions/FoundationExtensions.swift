/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
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

import Foundation

/// `CharacterSet` is a `Sendable` value type, so these need no isolation
/// annotation and no `NSCharacterSet` bridging at the point of use.
public extension CharacterSet {
	static let hexadecimalDigits = CharacterSet(charactersIn: "abcdefABCDEF0123456789")

	static let unreservedURICharacters = CharacterSet(
		charactersIn: "-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"
	)

	static let hostNameCharacters = CharacterSet(
		charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
	)

	static let asciiLetters = CharacterSet(
		charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	)
}

public extension NSNumber {
	var twoDigitString: String {
		int64Value.formatted(.number.precision(.integerLength(2...)).grouping(.never))
	}
}

public extension Bundle {
	/** The string `resource` names, looked up in this bundle.

	 `String(localized:)` resolves against `Bundle.main`, which inside an
	 application is the application — not the framework whose String Catalog
	 declares the key. A framework finds itself by naming one of its own classes,
	 and then has to ask that bundle for the string rather than go through the
	 resource. */
	func localizedString(for resource: LocalizedStringResource) -> String {
		localizedString(forKey: resource.key, value: nil, table: resource.table)
	}

	/// The same lookup, with `arguments` substituted into the result.
	func localizedString(for resource: LocalizedStringResource, arguments: [CVarArg]) -> String {
		String(format: localizedString(for: resource), arguments: arguments)
	}
}

public extension Error {
	@inlinable
	var code: Int {
		(self as NSError).code
	}

	@inlinable
	var domain: String {
		(self as NSError).domain
	}
}

public extension ComparisonResult {
	/// This ascending result as `order` asks for it. Every `SortComparator` a
	/// table column is built from needs the same flip, and each one used to
	/// carry its own copy of it.
	func ordered(by order: SortOrder) -> ComparisonResult {
		guard order == .reverse else { return self }

		return switch self {
		case .orderedAscending: .orderedDescending
		case .orderedDescending: .orderedAscending
		case .orderedSame: .orderedSame
		}
	}
}

public extension Int {
	@inlinable
	var isValidInternetPort: Bool {
		self > 0 && self <= 65535
	}
}

public extension URL {
	/// The receiver's path with the user's home directory replaced by `~`,
	/// for display. `nil` when the receiver is not a file URL.
	var standardizedTildePath: String? {
		guard isFileURL else {
			return nil
		}

		return path.standardizedTildePath
	}
}
