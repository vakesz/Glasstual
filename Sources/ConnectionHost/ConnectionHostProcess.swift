// Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

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
final class ConnectionHostProcess: NSObject, RemoteConnectionServerProtocol {
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

private let listenerDelegateLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ConnectionHostListenerDelegate"
)

final class ConnectionHostListenerDelegate: NSObject, NSXPCListenerDelegate {
	/** What a connecting peer has to be: the application this service is
	 embedded in, signed with the same certificate.

	 The service bundle sits at `Contents/XPCServices/` inside that application,
	 which is where its identifier is read from rather than repeated here. */
	private let peerRequirement: String? = {
		let applicationURL = Bundle.main.bundleURL
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		guard let applicationIdentifier = Bundle(url: applicationURL)?.bundleIdentifier else {
			return nil
		}
		return RemoteConnectionPeerRequirement.requirement(forCurrentProcessAnd: applicationIdentifier)
	}()

	func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
		if let peerRequirement {
			/* Enforced by NSXPC on every message: a peer that does not satisfy
			 it never reaches the exported object. */
			connection.setCodeSigningRequirement(peerRequirement)
		} else {
			listenerDelegateLogger.error("The connection host is not signed; accepting its peer unverified")
		}

		connection.exportedInterface = RemoteConnectionInterface.server()
		connection.remoteObjectInterface = RemoteConnectionInterface.client()

		/* The host owns every piece of mutable state. The connection stays out
		 here — it is not Sendable — and only the client proxy, which is, crosses
		 into the actor. */
		guard let client = connection.remoteObjectProxy as? any RemoteConnectionClientProtocol else {
			listenerDelegateLogger.error("Client does not conform to the remote connection client protocol")

			return false
		}

		let host = ConnectionHost(client: client)
		connection.exportedObject = ConnectionHostProcess(host: host)

		connection.interruptionHandler = {
			listenerDelegateLogger.debug("Client connection interrupted")

			Task { await host.detach() }
		}
		connection.invalidationHandler = {
			listenerDelegateLogger.debug("Client connection invalidated")

			Task { await host.detach() }
		}

		connection.resume()

		return true
	}
}
