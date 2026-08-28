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

import Foundation

/// Whether a plist-shaped value read out of a dictionary or an array counts as
/// empty, for the helpers that strip empty entries before writing preferences.
///
/// `NSNull` is empty because that is how a missing value survives a plist round
/// trip. A value of a type with no notion of emptiness -- a number, a date -- is
/// not empty.
///
/// The three copies of this cascade that used to live in `NSDictionaryHelper`,
/// `NSArrayHelper` and `XRGlobalModels` had drifted only in their names.
func isEmptyValue(_ value: Any) -> Bool {
	switch value {
	case is NSNull:
		true
	case let string as String:
		string.isEmpty
	case let data as Data:
		data.isEmpty
	case let array as NSArray:
		array.count == 0
	case let dictionary as NSDictionary:
		dictionary.count == 0
	case let set as NSSet:
		set.count == 0
	case let orderedSet as NSOrderedSet:
		/* Listed explicitly: NSOrderedSet, unlike the three above, has no Swift
		 Collection bridge to fall through to. */
		orderedSet.count == 0
	case let indexSet as NSIndexSet:
		indexSet.count == 0
	case let attributedString as NSAttributedString:
		attributedString.length == 0
	case let hashTable as NSHashTable<AnyObject>:
		hashTable.count == 0
	case let mapTable as NSMapTable<AnyObject, AnyObject>:
		mapTable.count == 0
	case let pointerArray as NSPointerArray:
		pointerArray.count == 0
	case let collection as any Collection:
		collection.isEmpty
	default:
		false
	}
}
