// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

extension ConnectionSocket {
	// MARK: - Connection task

	/** Dials, and dials once more without forward secrecy when the peer accepted
	 none of the suites the selection offered.

	 The selected suites are offered first on every connect, so a server that has
	 since been fixed is reached the right way with no state to clear. The second
	 dial is part of the same connection attempt: it costs the application no
	 reconnect-backoff step, because as far as the application is concerned this
	 transport has not failed yet. */
	func runConnection() async {
		let failure = await dial(offeringLegacyCipherSuites: false)

		guard retriesWithoutForwardSecrecy else {
			onDisconnect(with: failure)

			return
		}

		prepareForLegacyDial()

		/* The second dial can establish and then run for hours. Its eventual
		 failure belongs to that connection, and a certificate rejection during
		 its handshake must also retain its own classification. */
		let legacyFailure = await dial(offeringLegacyCipherSuites: true)

		onDisconnect(with: legacyFailure)
	}

	/** One dial, and the reason it ended — nil when it ended with none.

	 Its own task, so that ending the dial — the owner's close, or this
	 transport's answer to a failure — cancels the dial without cancelling the
	 supervisor that may still have the legacy retry to run. */
	func dial(offeringLegacyCipherSuites offering: Bool) async -> ConnectionError? {
		offeredLegacyCipherSuites = offering

		let task = Task { [weak self] () -> ConnectionError? in
			guard let self else { return nil }

			return await performDial(offeringLegacyCipherSuites: offering)
		}

		dialTask = task

		let failure = await task.value

		dialTask = nil

		return failure
	}

	func performDial(offeringLegacyCipherSuites offering: Bool) async -> ConnectionError? {
		do {
			let endpoint = NWEndpoint.hostPort(
				host: NWEndpoint.Host(config.serverAddress),
				port: NWEndpoint.Port(integerLiteral: config.serverPort)
			)
			if config.connectionPrefersSecuredConnection {
				let tls = try constructedTLS(offeringLegacyCipherSuites: offering)
				let parameters = NWParametersBuilder.parameters { tls }
				try ConnectionParameters.applyProxy(config, to: parameters.parameters, uniqueIdentifier: uniqueIdentifier)

				try await withNetworkConnection(
					to: endpoint,
					using: parameters
				) { connection in
					try await use(.tls(connection))
				}
			} else {
				let parameters = NWParametersBuilder.parameters { ConnectionParameters.tcp(for: config) }
				try ConnectionParameters.applyProxy(config, to: parameters.parameters, uniqueIdentifier: uniqueIdentifier)

				try await withNetworkConnection(
					to: endpoint,
					using: parameters
				) { connection in
					try await use(.tcp(connection))
				}
			}

			return alternateDisconnectError
		} catch is CancellationError {
			return alternateDisconnectError
		} catch {
			noteTLSFailure(error)

			return alternateDisconnectError ?? ConnectionError.translating(error)
		}
	}

	/** Whether the dial that just ended is the one failure this transport answers
	 by dialling again itself.

	 Everything the connection has done so far is part of the question: a
	 transport that connected, secured itself or saw the peer's certificate did
	 agree on a suite, and a close the owner asked for is not something to answer
	 with another dial. */
	var retriesWithoutForwardSecrecy: Bool {
		SecureTransportSupport.retriesWithLegacyCipherSuites(
			afterErrorCode: tlsFailureCode,
			legacySuitesAlreadyOffered: offeredLegacyCipherSuites,
			peerCertificateSeen: trustExport.certificateChain.isEmpty == false
		)
			&& closedByOwner == false
			&& connected == false
			&& secured == false
	}

	/// Puts the transport back where ``open()`` left it, for the one extra dial.
	func prepareForLegacyDial() {
		let identifier = uniqueIdentifier

		ConnectionHostLog.connection.notice(
			"Connection \(identifier, privacy: .public) found no cipher suite in common; offering the legacy suites once"
		)

		tlsFailureCode = nil
		alternateDisconnectError = nil
		trustExport = TLSTrustExport()
		connection = nil
		phase = .connecting
		dialGeneration += 1

		framer.reset()

		config.diagnostics?.record(.transportStarted)
		scheduleConnectTimeout()
	}

	/// Records the OSStatus of a TLS failure, which is what the legacy retry is
	/// decided from.
	func noteTLSFailure(_ error: any Error) {
		switch error {
		case let .tls(code) as NWError:
			tlsFailureCode = Int(code)
		case let error as NSError where SecureTransportSupport.isTLSError(error):
			tlsFailureCode = error.code
		default:
			break
		}
	}

	func use(_ connection: TransportConnection) async throws {
		self.connection = connection
		let generation = dialGeneration

		try Task.checkCancellation()

		/* Typed connections establish lazily when the first operation starts.
		 Network.framework holds sends behind DNS, proxy and TLS establishment;
		 a failed handshake is reported by the first async operation. So the
		 connection handed to us here has no TLS metadata yet, and what was
		 negotiated is only knowable once it reports itself ready. */
		let transitions = connection.stateTransitions()

		let readiness = Task { [weak self] in
			for await transition in transitions {
				switch transition {
				case .ready:
					await self?.onReady(generation: generation)
				case let .failed(error):
					await self?.onTransportFailure(error, generation: generation)
				}
			}
		}

		defer { readiness.cancel() }

		try await read(from: connection, generation: generation)
	}

	func onConnect() {
		cancelConnectTimeout()

		phase = .connected

		/* When a proxy is in use the remote endpoint is the proxy, not the
		 server, so report nil as the host contract asks. */
		events.yield(.connected(host: proxyEndpoint == nil ? connectedHost : nil))
	}

	/// The transport finished establishing, so the handshake — if there was
	/// one — has run and its metadata is readable.
	func onReady(generation: Int) {
		guard generation == dialGeneration, connecting, disconnecting == false else { return }

		config.diagnostics?.record(.transportReady)
		onConnect()
		onSecured()
	}

	/// The transport reported it cannot establish. Only an establishing
	/// connection is closed here: once ready, a drop is reported by the read
	/// that fails, and a close already under way keeps its own error.
	func onTransportFailure(_ error: NWError, generation: Int) {
		guard generation == dialGeneration, connecting, connected == false, disconnecting == false else { return }

		config.diagnostics?.record(.transportFailed)
		noteTLSFailure(error)
		fail(with: ConnectionError.translating(error))
	}

	func onSecured() {
		/* Announced once. A plain TCP connection has no metadata to report and
		 so never becomes secured; a connection that drops back to preparing and
		 returns to ready negotiated nothing new. */
		guard secured == false,
		      let protocolVersion = tlsNegotiatedProtocol,
		      let cipherSuite = tlsNegotiatedCipherSuite
		else {
			return
		}

		secured = true

		events.yield(.secured(protocolVersion: protocolVersion, cipherSuite: cipherSuite))
	}

	/// Reports the transport gone, with the reason the dials it ran settled on.
	func onDisconnect(with error: ConnectionError?) {
		resetState()
		disconnectEventPending = true

		events.yield(.disconnected(error))

		/* Nothing follows a disconnect, so the host's event loop can end here
		 rather than waiting on a stream nobody will write to again. */
		events.finish()
	}
}
