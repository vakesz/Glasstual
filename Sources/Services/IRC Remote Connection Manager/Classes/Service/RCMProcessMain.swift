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

import CocoaExtensions
import Foundation

/// The object NSXPC exports for a connection host.
///
/// It holds the connection — which is not `Sendable` and so passes nowhere —
/// and the host actor, which owns every piece of state. Each `@objc` call is a
/// one-line hop into the actor.
@objc(RCMProcessMain)
final class RemoteConnectionProcess: NSObject, RemoteConnectionServerProtocol {
	private let host: ConnectionHost
	private let serviceConnection: NSXPCConnection

	init(host: ConnectionHost, connection: NSXPCConnection) {
		self.host = host
		serviceConnection = connection

		super.init()

		Logging.setDefaultSubsystem(toMainBundleCategory: "General")
	}

	func open(with config: ConnectionConfigEnvelope) {
		let config = config.config

		Task { [host] in
			await host.open(with: config)
		}
	}

	func close() {
		Task { [host] in
			await host.close()
		}
	}

	func send(_ data: Data) {
		send(data, bypassQueue: false)
	}

	func send(_ data: Data, bypassQueue: Bool) {
		Task { [host] in
			await host.send(data, bypassQueue: bypassQueue)
		}
	}

	func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver) {
		/* The caller treats this as a reply block, so it has to be invoked on
		 every path. */
		Task { [host] in
			await receiver(host.secureConnectionInformation())
		}
	}

	func enforceFloodControl() {
		Task { [host] in
			await host.enforceFloodControl()
		}
	}

	func clearSendQueue() {
		Task { [host] in
			await host.clearSendQueue()
		}
	}

	func enableAppNap() {
		Task { [host] in
			await host.enableAppNap()
		}
	}

	func disableAppNap() {
		Task { [host] in
			await host.disableAppNap()
		}
	}

	func enableSuddenTermination() {
		Task { [host] in
			await host.enableSuddenTermination()
		}
	}

	func disableSuddenTermination() {
		Task { [host] in
			await host.disableSuddenTermination()
		}
	}
}
