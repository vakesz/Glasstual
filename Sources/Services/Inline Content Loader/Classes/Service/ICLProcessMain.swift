/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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
import InlineContentKit

/// The object NSXPC exports for an inline-content connection.
///
/// It holds the connection — which is not `Sendable` and so passes nowhere —
/// and the service actor, which owns every piece of state. Each `@objc` call is
/// a one-line hop into the actor.
@objc(ICLProcessMain)
final class InlineContentProcess: NSObject, InlineContentServerProtocol {
	private let service: InlineContentService
	private let serviceConnection: NSXPCConnection

	init(service: InlineContentService, connection: NSXPCConnection) {
		self.service = service
		serviceConnection = connection

		super.init()
	}

	func warmServiceByLoadingPlugins() {
		/* The modules are linked into the service and listed in
		 InlineContentModuleRegistry, so there is nothing left to load. The call
		 stays because it is part of the XPC protocol the application speaks. */
	}

	func warmService(with preferences: InlineContentServicePreferences) {
		Task { [service] in
			await service.warmService(with: preferences)
		}
	}

	func process(
		_ url: URL,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt,
		inView viewIdentifier: String
	) {
		let values = InlineContentPayloadValues(
			url: url,
			uniqueIdentifier: uniqueIdentifier,
			lineNumber: lineNumber,
			index: index,
			viewIdentifier: viewIdentifier
		)

		Task { [service] in
			await service.process(values)
		}
	}

	func process(_ payload: InlineContentPayload) {
		let values = payload.values

		Task { [service] in
			await service.process(values)
		}
	}
}
