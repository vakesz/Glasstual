/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

@objc(IRCSTSCapabilityValues)
public final nonisolated class STSCapabilityValues: NSObject {
	@objc public private(set) var port: UInt16 = 0
	@objc public private(set) var hasDuration = false
	@objc public private(set) var duration: TimeInterval = 0
	@objc public private(set) var preload = false

	@objc(valuesFromCapabilityValues:)
	public static func values(fromCapabilityValues values: [String]) -> STSCapabilityValues? {
		let result = STSCapabilityValues()
		var recognizedKey = false

		for value in values {
			let (key, keyValue) = split(value: value)

			switch key.lowercased() {
			case "port":
				if isDecimalNumber(keyValue) {
					let port = (keyValue as NSString).integerValue

					if port > 0, port <= UInt16.max {
						result.port = UInt16(port)
					}
				}

				recognizedKey = true
			case "duration":
				if isDecimalNumber(keyValue) {
					result.hasDuration = true
					result.duration = (keyValue as NSString).doubleValue
				}

				recognizedKey = true
			case "preload":
				result.preload = true
				recognizedKey = true
			default:
				break
			}
		}

		return recognizedKey ? result : nil
	}

	override public var description: String {
		"<\(NSStringFromClass(type(of: self))) port=\(port) duration=\(String(format: "%.0f", duration)) preload=\(preload ? 1 : 0)>"
	}

	private static func split(value: String) -> (key: String, value: String) {
		guard let equalsIndex = value.firstIndex(of: "=") else {
			return (value, "")
		}

		return (
			String(value[..<equalsIndex]),
			String(value[value.index(after: equalsIndex)...])
		)
	}

	private static func isDecimalNumber(_ value: String) -> Bool {
		value.isEmpty == false && value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
	}
}
