/* *********************************************************************
 *
 *         Copyright (c) 2026 Codeux Software, LLC & respective contributors.
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
import os

private let propertyListModelLogger = Logger(
	subsystem: "com.vakesz.glasstual",
	category: "PropertyListModel"
)

/** Moves `Codable` value models between Swift and the property-list
 dictionaries Glasstual keeps in `UserDefaults`.

 Everything on disk was written by `NSDictionary`, so the round trip goes
 through `PropertyListSerialization`: the same numbers, booleans, strings, data
 and nested containers come back out, which is what keeps an existing
 preferences file readable by this build and readable again by the last one. */
public enum PropertyListModel {
	/// Decodes `dictionary`, or returns `nil` and logs when it does not describe
	/// a `Model`. Callers skip the malformed entry rather than aborting.
	public static func decode<Model: Decodable>(
		_ type: Model.Type,
		from dictionary: [String: PropertyListValue]
	) -> Model? {
		do {
			let data = try PropertyListSerialization.data(
				fromPropertyList: dictionary.propertyListObject,
				format: .binary,
				options: 0
			)

			return try PropertyListDecoder().decode(type, from: data)
		} catch {
			propertyListModelLogger.error(
				"Could not read a \(String(describing: type), privacy: .public): \(error, privacy: .public)"
			)

			return nil
		}
	}

	/// Encodes `value` into the dictionary shape the preferences file stores.
	/// Returns an empty dictionary and logs if the model is not representable.
	public static func encode(_ value: some Encodable) -> [String: PropertyListValue] {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary

		do {
			let data = try encoder.encode(value)
			let plist = try PropertyListSerialization.propertyList(
				from: data,
				options: [],
				format: nil
			)

			/* `Any` is what the serializer returns and where it stops: the
			 dictionary is narrowed here so no caller sees an untyped value. */
			guard let dictionary = [String: PropertyListValue](propertyList: plist) else {
				propertyListModelLogger.error("A model encoded to something other than a dictionary")

				return [:]
			}

			return dictionary
		} catch {
			let modelName = String(describing: Swift.type(of: value))
			propertyListModelLogger.error(
				"Could not write a \(modelName, privacy: .public): \(error, privacy: .public)"
			)

			return [:]
		}
	}
}

public extension KeyedDecodingContainer {
	/** Reads `key`, falling back to the first `aliases` entry that is present.

	 Configuration dictionaries written by earlier releases spell several
	 settings differently — `ignoreCTCP` for `ignoreClientToClientProtocol`, and
	 so on. The canonical key wins whenever both are present. */
	func decode<Value: Decodable>(
		_ type: Value.Type,
		forKey key: Key,
		aliases: [Key],
		default defaultValue: Value
	) -> Value {
		for candidate in [key] + aliases {
			if let value = try? decodeIfPresent(type, forKey: candidate) {
				return value
			}
		}

		return defaultValue
	}

	/// As above, but yields `nil` when neither the canonical key nor any alias
	/// is present, so an absent optional stays absent instead of being wiped.
	func decodeOptional<Value: Decodable>(
		_ type: Value.Type,
		forKey key: Key,
		aliases: [Key] = []
	) -> Value? {
		for candidate in [key] + aliases {
			if let value = try? decodeIfPresent(type, forKey: candidate), let value = value as Value? {
				return value
			}
		}

		return nil
	}
}
