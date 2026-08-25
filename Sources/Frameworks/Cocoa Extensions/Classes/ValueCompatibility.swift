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

import Foundation

extension NSValue {
	@objc(valueWithPrimitive:withType:)
	class func textual_value(withPrimitive value: UnsafeMutableRawPointer?,
	                         withType type: UnsafePointer<CChar>) -> Any
	{
		let pointerValue = UInt(bitPattern: value)

		switch UnicodeScalar(UInt8(bitPattern: type.pointee)) {
		case "@":
			guard let value else { return NSNull() }
			return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
		case "s": return NSNumber(value: Int16(truncatingIfNeeded: pointerValue))
		case "S": return NSNumber(value: UInt16(truncatingIfNeeded: pointerValue))
		case "i": return NSNumber(value: Int32(truncatingIfNeeded: pointerValue))
		case "I": return NSNumber(value: UInt32(truncatingIfNeeded: pointerValue))
		case "l": return NSNumber(value: Int(truncatingIfNeeded: pointerValue))
		case "L": return NSNumber(value: UInt(truncatingIfNeeded: pointerValue))
		case "q": return NSNumber(value: Int64(truncatingIfNeeded: pointerValue))
		case "Q": return NSNumber(value: UInt64(truncatingIfNeeded: pointerValue))
		case "f": return NSNumber(value: value?.load(as: Float.self) ?? 0)
		case "d": return NSNumber(value: value?.load(as: Double.self) ?? 0)
		case "C": return NSNumber(value: UInt8(truncatingIfNeeded: pointerValue))
		case "c":
			if pointerValue == 0 || pointerValue == 1 {
				return NSNumber(value: pointerValue == 1)
			}
			return NSNumber(value: Int8(truncatingIfNeeded: pointerValue))
		default:
			guard let value else { return NSNull() }
			return NSValue(bytes: value, objCType: type)
		}
	}
}
