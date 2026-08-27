/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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
import ObjectiveC.runtime

public enum PluginHost {
	public static let zncPlaybackCapabilityRawValue: UInt = 1 << 27
	public static let defaultMaximumNicknameLength: UInt = 50

	public static func maximumNicknameLength(on client: AnyObject) -> UInt {
		guard HostRuntime.bool(client, selectorNamed: "isConnectedToZNC") == false,
		      let supportInfo = HostRuntime.object(client, selectorNamed: "supportInfo"),
		      HostRuntime.bool(supportInfo, selectorNamed: "configurationReceived") == true,
		      let configuredMaximum = HostRuntime.uint(supportInfo, selectorNamed: "maximumNicknameLength"),
		      configuredMaximum > 0
		else {
			return defaultMaximumNicknameLength
		}

		return configuredMaximum
	}

	public static func utilityChannel(named name: String, on client: AnyObject) -> AnyObject? {
		let selector = NSSelectorFromString("findChannelOrCreate:isUtility:")
		guard client.responds(to: selector),
		      let method = class_getInstanceMethod(type(of: client), selector)
		else {
			return nil
		}

		typealias Implementation = @convention(c) (
			AnyObject,
			Selector,
			NSString,
			Bool
		) -> Unmanaged<AnyObject>?

		let implementation = unsafeBitCast(method_getImplementation(method), to: Implementation.self)
		return implementation(client, selector, name as NSString, true)?.takeUnretainedValue()
	}

	public static func reloadTreeGroup(_ item: AnyObject, in window: AnyObject) {
		let selector = NSSelectorFromString("reloadTreeGroup:")
		guard window.responds(to: selector),
		      let method = class_getInstanceMethod(type(of: window), selector)
		else {
			return
		}

		typealias Implementation = @convention(c) (AnyObject, Selector, AnyObject) -> Void
		let implementation = unsafeBitCast(method_getImplementation(method), to: Implementation.self)
		implementation(window, selector, item)
	}
}
