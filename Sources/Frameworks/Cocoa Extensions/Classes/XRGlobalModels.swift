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
import ObjectiveC.runtime
import os

private typealias ObjectiveCCountImplementation = @convention(c) (AnyObject, Selector) -> UInt

private enum GlobalModelSupport {
	static let defaultQueuePriority = 0
	static let highQueuePriority = 2
	static let lowQueuePriority = -2
	static let backgroundQueuePriority = Int(Int16.min)

	static let logger = Logger(
		subsystem: "com.vakesz.glasstual.frameworks.CocoaExtensions",
		category: "Framework"
	)

	static func countReturned(by selector: Selector, from object: AnyObject) -> UInt? {
		guard
			let objectClass = object_getClass(object),
			let method = class_getInstanceMethod(objectClass, selector)
		else {
			return nil
		}

		let implementation = method_getImplementation(method)
		let countImplementation = unsafeBitCast(implementation, to: ObjectiveCCountImplementation.self)

		return countImplementation(object, selector)
	}

	static func timer(
		on queue: DispatchQueue,
		block: @escaping @convention(block) () -> Void,
		delay: TimeInterval,
		repeats: Bool
	) -> DispatchSourceTimer? {
		precondition(delay >= 0, "Delay must not be negative")

		let timer = DispatchSource.makeTimerSource(queue: queue)
		let nanoseconds = Int(delay * Double(NSEC_PER_SEC))
		let deadline = DispatchTime.now() + .nanoseconds(nanoseconds)

		if repeats {
			timer.schedule(deadline: deadline, repeating: .nanoseconds(nanoseconds), leeway: .nanoseconds(0))
		} else {
			timer.schedule(deadline: deadline, repeating: .never, leeway: .nanoseconds(0))
		}

		timer.setEventHandler(handler: block)

		return timer
	}
}

@_cdecl("NSObjectIsEmpty")
public func cocoaExtensionsObjectIsEmpty(_ object: AnyObject?) -> Bool {
	guard let object else {
		return true
	}

	if let length = GlobalModelSupport.countReturned(by: #selector(getter: NSString.length), from: object) {
		return length < 1
	}

	if let count = GlobalModelSupport.countReturned(by: #selector(getter: NSArray.count), from: object) {
		return count < 1
	}

	return object is NSNull
}

@_cdecl("XRScheduleBlockOnGlobalQueue")
public func cocoaExtensionsScheduleBlockOnGlobalQueue(
	_ block: @escaping @convention(block) () -> Void,
	_ delay: TimeInterval
) -> AnyObject? {
	cocoaExtensionsScheduleBlockOnGlobalQueueWithPriority(
		block,
		delay,
		GlobalModelSupport.defaultQueuePriority
	)
}

@_cdecl("XRScheduleBlockOnGlobalQueueWithPriority")
public func cocoaExtensionsScheduleBlockOnGlobalQueueWithPriority(
	_ block: @escaping @convention(block) () -> Void,
	_ delay: TimeInterval,
	_ priority: Int
) -> AnyObject? {
	let queue = DispatchQueue.global(qos: qualityOfService(for: priority))

	return GlobalModelSupport.timer(on: queue, block: block, delay: delay, repeats: false)
}

@_cdecl("XRScheduleBlockOnMainQueue")
public func cocoaExtensionsScheduleBlockOnMainQueue(
	_ block: @escaping @convention(block) () -> Void,
	_ delay: TimeInterval
) -> AnyObject? {
	GlobalModelSupport.timer(on: .main, block: block, delay: delay, repeats: false)
}

@_cdecl("XRScheduleBlockOnQueue")
public func cocoaExtensionsScheduleBlockOnQueue(
	_ queue: DispatchQueue,
	_ block: @escaping @convention(block) () -> Void,
	_ delay: TimeInterval,
	_ repeatTimer: Bool
) -> AnyObject? {
	GlobalModelSupport.timer(on: queue, block: block, delay: delay, repeats: repeatTimer)
}

@_cdecl("XRResumeScheduledBlock")
public func cocoaExtensionsResumeScheduledBlock(_ blockSource: AnyObject) {
	(blockSource as? DispatchSourceTimer)?.resume()
}

@_cdecl("XRCancelScheduledBlock")
public func cocoaExtensionsCancelScheduledBlock(_ blockSource: AnyObject) {
	(blockSource as? DispatchSourceTimer)?.cancel()
}

@_cdecl("XRExchangeInstanceMethod")
public func cocoaExtensionsExchangeInstanceMethod(
	_ className: NSString,
	_ originalMethod: NSString,
	_ replacementMethod: NSString
) {
	guard let objectClass = NSClassFromString(className as String) else {
		GlobalModelSupport.logger.error("Cannot swizzle class \(className, privacy: .public): class not found")
		return
	}

	let originalSelector = NSSelectorFromString(originalMethod as String)
	let replacementSelector = NSSelectorFromString(replacementMethod as String)

	guard
		let original = class_getInstanceMethod(objectClass, originalSelector),
		let replacement = class_getInstanceMethod(objectClass, replacementSelector)
	else {
		GlobalModelSupport.logger.error(
			"Cannot swizzle -[\(className, privacy: .public) \(originalMethod, privacy: .public)] with \(replacementMethod, privacy: .public): method not found"
		)
		return
	}

	let methodAdded = class_addMethod(
		objectClass,
		originalSelector,
		method_getImplementation(replacement),
		method_getTypeEncoding(replacement)
	)

	if methodAdded {
		class_replaceMethod(
			objectClass,
			replacementSelector,
			method_getImplementation(original),
			method_getTypeEncoding(original)
		)
	} else {
		method_exchangeImplementations(original, replacement)
	}
}

private func qualityOfService(for priority: Int) -> DispatchQoS.QoSClass {
	switch priority {
	case GlobalModelSupport.highQueuePriority:
		.userInitiated
	case GlobalModelSupport.lowQueuePriority:
		.utility
	case GlobalModelSupport.backgroundQueuePriority:
		.background
	default:
		.default
	}
}
