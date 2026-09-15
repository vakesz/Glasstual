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

/// One thing the application asked the host to do.
///
/// The commands are closures so that they can wait their turn in a queue. NSXPC
/// delivers messages in order on its own serial queue; putting each one in here
/// is what carries that order across to the actor.
private typealias HostCommand = @Sendable (ConnectionHost) async -> Void

/// The object NSXPC exports for a connection host.
///
/// Every exported method is a one-line hop into `ConnectionHost`, which owns
/// all of the state. The hop goes through a single stream that one task drains
/// in order: an unstructured `Task` per call would have handed the messages to
/// the global executor, which schedules them against each other however it
/// likes, so `open` could land after the first `send` and two sends could swap
/// places on the wire.
final class RemoteConnectionProcess: NSObject, RemoteConnectionServerProtocol {
	private let commands: AsyncStream<HostCommand>.Continuation
	private let commandTask: Task<Void, Never>

	init(host: ConnectionHost) {
		let (commands, continuation) = AsyncStream<HostCommand>.makeStream(
			/* Nothing the application asks for may be dropped, and a command
			 that takes a while (a write behind an unresponsive peer) must not
			 cost the ones queued behind it. */
			bufferingPolicy: .unbounded
		)

		self.commands = continuation
		commandTask = Task {
			for await command in commands {
				guard Task.isCancelled == false else { return }
				await command(host)
			}
		}

		super.init()

		Logging.setDefaultSubsystem(toMainBundleCategory: "General")
	}

	deinit {
		commandTask.cancel()
		commands.finish()
	}

	func open(with config: ConnectionConfigEnvelope) {
		let config = config.config
		commands.yield { await $0.open(with: config) }
	}

	func close() {
		commands.yield { await $0.close() }
	}

	func send(_ data: Data) {
		send(data, bypassQueue: false)
	}

	func send(_ data: Data, bypassQueue: Bool) {
		commands.yield { await $0.send(data, bypassQueue: bypassQueue) }
	}

	func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver) {
		/* The caller treats this as a reply block, so it has to be invoked on
		 every path. */
		commands.yield { await receiver($0.secureConnectionInformation()) }
	}

	func enforceFloodControl() {
		commands.yield { await $0.enforceFloodControl() }
	}

	func clearSendQueue() {
		commands.yield { await $0.clearSendQueue() }
	}

	func disableAppNap() {
		commands.yield { await $0.disableAppNap() }
	}

	func disableSuddenTermination() {
		commands.yield { await $0.disableSuddenTermination() }
	}
}
