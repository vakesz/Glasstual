// Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** The service's entry point: every connection the application opens arrives
 here, is checked against the code-signing requirement, and is given a host of
 its own. */
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
		#if DEBUG
			let allowsUnverifiedPeer = true
		#else
			let allowsUnverifiedPeer = false
		#endif

		switch ConnectionPeerAdmission.decide(
			requirement: peerRequirement, allowsUnverifiedPeer: allowsUnverifiedPeer
		) {
		case let .enforce(requirement):
			/* Enforced by NSXPC on every message: a peer that does not satisfy
			 it never reaches the exported object. */
			connection.setCodeSigningRequirement(requirement)
		case .acceptUnverified:
			/* Without a requirement there is nothing to check the peer against,
			 and an unverified peer drives a host that dials arbitrary servers.
			 Only a Debug build, which unsigned local builds and the test and
			 E2E harnesses run, may go on; a Release build refuses. */
			ConnectionHostLog.listener.error("The connection host is not signed; accepting its peer unverified")
		case .refuse:
			ConnectionHostLog.listener.fault("The connection host is not signed; refusing its peer")

			return false
		}

		connection.exportedInterface = RemoteConnectionInterface.server()
		connection.remoteObjectInterface = RemoteConnectionInterface.client()

		/* The host owns every piece of mutable state. The connection stays out
		 here — it is not Sendable — and only the client proxy, which is, crosses
		 into the actor. */
		guard let client = connection.remoteObjectProxy as? any RemoteConnectionClientProtocol else {
			ConnectionHostLog.listener.error("Client does not conform to the remote connection client protocol")

			return false
		}

		let host = ConnectionHost(client: client)
		connection.exportedObject = ConnectionHostProcess(host: host)

		connection.interruptionHandler = {
			ConnectionHostLog.listener.debug("Client connection interrupted")

			Task { await host.detach() }
		}
		connection.invalidationHandler = {
			ConnectionHostLog.listener.debug("Client connection invalidated")

			Task { await host.detach() }
		}

		connection.resume()

		return true
	}
}

let delegate = ConnectionHostListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
