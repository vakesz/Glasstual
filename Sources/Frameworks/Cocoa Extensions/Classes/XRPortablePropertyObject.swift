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
import ObjectiveC.runtime

@objc(XRPortablePropertyObjectPrototype)
public protocol PortablePropertyObjectPrototype: NSObjectProtocol {
	@objc(populateDefaultsPreflight)
	func populateDefaultsPreflight()
	@objc(populateDefaultsPostflight)
	func populateDefaultsPostflight()
	@objc(initializedClassHealthCheck)
	func initializedClassHealthCheck()
	@objc(populateDuringCopy:mutableCopy:)
	func populateDuringCopy(_ newObject: PortablePropertyObject, mutableCopy: Bool)
	@objc(populateDuringUniqueCopy:mutableCopy:)
	func populateDuringUniqueCopy(_ newObject: PortablePropertyObject, mutableCopy: Bool)
	@objc(populateWithDecoder:)
	func populate(with decoder: NSCoder) -> Bool
}

enum PortablePropertyRuntime {
	static func allocate<T: NSObject>(_ classReference: AnyObject, as _: T.Type) -> T {
		let objectClass: AnyClass = if object_isClass(classReference) {
			unsafeBitCast(classReference, to: AnyClass.self)
		} else {
			type(of: classReference)
		}

		guard
			let object = class_createInstance(objectClass, 0) as? T
		else {
			preconditionFailure("Unable to allocate portable property copy")
		}

		return object
	}

	static func initialize<T: NSObject>(_ object: T, selector: Selector, argument: AnyObject? = nil) -> T {
		let result: Unmanaged<AnyObject>? = if let argument {
			object.perform(selector, with: argument)
		} else {
			object.perform(selector)
		}

		/* `class_createInstance` already gives this scope ownership of the
		 allocated object. Treat the initializer result as borrowed so the
		 allocation and returned reference do not each consume the same retain. */
		guard let initialized = result?.takeUnretainedValue() as? T else {
			preconditionFailure("Portable property initializer returned an incompatible object")
		}

		return initialized
	}
}

@objc(XRPortablePropertyObject)
@objcMembers
open class PortablePropertyObject: NSObject, NSCopying, NSMutableCopying, NSSecureCoding,
	PortablePropertyObjectPrototype
{
	public internal(set) dynamic var initializedAsCopy: Bool {
		get {
			(objc_getAssociatedObject(self, initializedAsCopyAssociationKey) as? NSNumber)?.boolValue ?? false
		}
		set {
			objc_setAssociatedObject(
				self,
				initializedAsCopyAssociationKey,
				NSNumber(value: newValue),
				.OBJC_ASSOCIATION_RETAIN_NONATOMIC
			)
		}
	}

	override public init() {
		super.init()
	}

	public required init?(coder: NSCoder) {
		super.init()

		populateDefaultsPreflight()

		guard populate(with: coder) else {
			return nil
		}

		populateDefaultsPostflight()
		initializedClassHealthCheck()
	}

	open dynamic class var supportsSecureCoding: Bool {
		false
	}

	open dynamic class var isMutable: Bool {
		false
	}

	open dynamic var isMutable: Bool {
		type(of: self).isMutable
	}

	open dynamic var immutableClass: PortablePropertyObject {
		assert(
			!isMutable,
			"A mutable portable property class must override immutableClass"
		)

		return self
	}

	open dynamic var mutableClass: PortablePropertyObject {
		assert(
			isMutable,
			"An immutable portable property class must override mutableClass"
		)

		return self
	}

	open dynamic var copyByReference: Bool {
		true
	}

	@objc(initOnCopy)
	open dynamic func initOnCopy() -> Self {
		self
	}

	@objc(initOnMutate)
	open dynamic func initOnMutate() -> Self {
		self
	}

	open dynamic func encode(with _: NSCoder) {
		doesNotRecognizeSelector(#selector(encode(with:)))
	}

	open dynamic func populateDefaultsPreflight() {}

	open dynamic func populateDefaultsPostflight() {}

	open dynamic func initializedClassHealthCheck() {}

	@objc(performInitialization)
	open dynamic func performInitialization() {}

	@objc(populateWithDecoder:)
	open dynamic func populate(with _: NSCoder) -> Bool {
		false
	}

	override open dynamic func isEqual(_ object: Any?) -> Bool {
		guard let object = object as AnyObject? else {
			return false
		}

		return object === self
	}

	open dynamic func copy(with _: NSZone? = nil) -> Any {
		if !isMutable, copyByReference {
			return self
		}

		return copy(asMutable: false)
	}

	open dynamic func mutableCopy(with _: NSZone? = nil) -> Any {
		copy(asMutable: true)
	}

	@objc(allocForCopyAsMutable:)
	open dynamic func allocForCopy(asMutable mutableCopy: Bool) -> Any {
		let classReference = mutableCopy ? mutableClass : immutableClass
		let object = PortablePropertyRuntime.allocate(classReference, as: PortablePropertyObject.self)
		object.initializedAsCopy = true

		return object
	}

	@objc(copyAsMutable:)
	open dynamic func copy(asMutable mutableCopy: Bool) -> Any {
		copy(asMutable: mutableCopy, uniquing: false)
	}

	@objc(copyAsMutable:uniquing:)
	open dynamic func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		let object = allocForCopy(asMutable: mutableCopy) as! PortablePropertyObject

		if uniquing {
			populateDuringUniqueCopy(object, mutableCopy: mutableCopy)
		} else {
			populateDuringCopy(object, mutableCopy: mutableCopy)
		}

		return PortablePropertyRuntime.initialize(object, selector: #selector(initOnCopy))
	}

	@objc(uniqueCopyAsMutable:)
	open dynamic func uniqueCopy(asMutable mutableCopy: Bool) -> Any {
		copy(asMutable: mutableCopy, uniquing: true)
	}

	open dynamic func uniqueCopy() -> Any {
		uniqueCopy(asMutable: false)
	}

	open dynamic func uniqueCopyMutable() -> Any {
		uniqueCopy(asMutable: true)
	}

	@objc(populateDuringCopy:mutableCopy:)
	open dynamic func populateDuringCopy(_: PortablePropertyObject, mutableCopy _: Bool) {
		doesNotRecognizeSelector(#selector(populateDuringCopy(_:mutableCopy:)))
	}

	@objc(populateDuringUniqueCopy:mutableCopy:)
	open dynamic func populateDuringUniqueCopy(_: PortablePropertyObject, mutableCopy _: Bool) {
		doesNotRecognizeSelector(#selector(populateDuringUniqueCopy(_:mutableCopy:)))
	}
}

private var initializedAsCopyAssociationKey: UnsafeRawPointer {
	unsafeBitCast(NSSelectorFromString("initializedAsCopy"), to: UnsafeRawPointer.self)
}
