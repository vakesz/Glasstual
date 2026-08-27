/* *********************************************************************
 *
 *           Copyright (c) 2024 Codeux Software, LLC
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

@objc(PortablePropertyDictTarget)
public enum PortablePropertyDictTarget: UInt {
	case `default`
	case copy
	case mutableCopy
	case cloud
}

@objc(XRPortablePropertyDictPrototype)
public protocol PortablePropertyDictPrototype: NSObjectProtocol {
	@objc(populateDictionaryValues:)
	func populateDictionaryValues(_ dictionary: [String: Any])
	@objc(dictionaryValueForTarget:)
	func dictionaryValue(for target: PortablePropertyDictTarget) -> [String: Any]
}

@objc(PortablePropertyDict)
@objcMembers
open class PortablePropertyDict: PortablePropertyObject, PortablePropertyDictPrototype {
	override public init() {
		super.init()
	}

	@objc(initWithDictionary:)
	public required init(dictionary: [String: Any]) {
		super.init()

		populateDefaultsPreflight()
		populateDictionaryValues(dictionary)
		populateDefaultsPostflight()
		initializedClassHealthCheck()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	open dynamic func populateDictionaryValues(_: [String: Any]) {}

	@objc(dictionaryValueForTarget:)
	open dynamic func dictionaryValue(for _: PortablePropertyDictTarget) -> [String: Any] {
		[:]
	}

	open dynamic var dictionaryValue: [String: Any] {
		dictionaryValue(for: .default)
	}

	open dynamic var dictionaryValueForCloud: [String: Any] {
		dictionaryValue(for: .cloud)
	}

	open dynamic var dictionaryValueForCopy: [String: Any] {
		dictionaryValue(for: .copy)
	}

	override open dynamic var immutableClass: PortablePropertyObject {
		super.immutableClass
	}

	override open dynamic var mutableClass: PortablePropertyObject {
		super.mutableClass
	}

	override open dynamic func isEqual(_ object: Any?) -> Bool {
		guard let object = object as? PortablePropertyDict else {
			return false
		}

		if object === self {
			return true
		}

		return NSDictionary(dictionary: dictionaryValue).isEqual(to: object.dictionaryValue)
	}

	override open dynamic var hash: Int {
		NSDictionary(dictionary: dictionaryValue).hash
	}

	override open dynamic func copy(asMutable mutableCopy: Bool, uniquing _: Bool) -> Any {
		let classReference = mutableCopy ? mutableClass : immutableClass
		let object = PortablePropertyRuntime.allocate(classReference, as: PortablePropertyDict.self)
		object.initializedAsCopy = true

		let target: PortablePropertyDictTarget = mutableCopy ? .mutableCopy : .copy
		let dictionary = dictionaryValue(for: target) as NSDictionary

		return PortablePropertyRuntime.initialize(
			object,
			selector: #selector(PortablePropertyDict.init(dictionary:)),
			argument: dictionary
		)
	}
}
