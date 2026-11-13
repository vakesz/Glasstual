// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
@testable import Glasstual
import Network
import Security
import Testing

/// Drives secure DCC transfers over loopback: against each other, and against
/// a raw TLS peer standing in for other clients.
@Suite("Secure DCC transfer over loopback")
struct DCCSecureTransferLoopbackTests {
	/// Starts `listener`, starts the transfer `dial` makes once the port is
	/// known, and returns both sides' events.
	private func run(
		listener: DCCTransfer,
		dial: (UInt16) -> DCCTransfer
	) async throws -> (listening: [DCCTransferEvent], dialling: [DCCTransferEvent]) {
		var local: [DCCTransferEvent] = []
		var remote: Task<[DCCTransferEvent], Never>?
		await listener.start()
		for await event in listener.events {
			local.append(event)
			if case let .listening(port) = event {
				let peer = dial(port)
				remote = TransferFixture.collectEvents(from: peer)
				await peer.start()
			}
		}
		return try (local, #require(await remote?.value))
	}

	@Test("A file crosses TLS byte for byte in either direction", .timeLimit(.minutes(1)), arguments: [true, false])
	func roundTrip(senderListens: Bool) async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let payload = TransferFixture.payload(byteCount: 5 * 1024 * 1024)
		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try payload.write(to: source)
		let sourceFile = try TransferFixture.source(source)
		let destinationFile = try TransferFixture.destination(destination)
		let size = UInt64(payload.count)

		let listenerIdentity = try DCCLocalIdentity.generate()
		let diallerIdentity = try DCCLocalIdentity.generate()
		let listenerLog = VerifierLog()
		let diallerLog = VerifierLog()
		let listenerConfiguration = try SecureFixture.configuration(identity: listenerIdentity, log: listenerLog)
		let diallerConfiguration = try SecureFixture.configuration(identity: diallerIdentity, log: diallerLog)

		let listener = DCCTransfer(config: SecureFixture.transfer(
			role: senderListens ? .sender : .receiver,
			endpoint: SecureFixture.listening,
			configuration: listenerConfiguration,
			file: senderListens ? sourceFile : destinationFile,
			fileSize: size
		))
		let (local, remote) = try await run(listener: listener) { port in
			DCCTransfer(config: SecureFixture.transfer(
				role: senderListens ? .receiver : .sender,
				endpoint: SecureFixture.dialling(port: port),
				configuration: diallerConfiguration,
				file: senderListens ? destinationFile : sourceFile,
				fileSize: size
			))
		}

		#expect(local.last.map(TransferFixture.isFinished) == true)
		#expect(remote.last.map(TransferFixture.isFinished) == true)
		try #expect(SHA256.hash(data: Data(contentsOf: destination)) == SHA256.hash(data: payload))

		let listenerSession = try #require(local.lazy.compactMap(SecureFixture.session).first ?? nil)
		let diallerSession = try #require(remote.lazy.compactMap(SecureFixture.session).first ?? nil)
		#expect(listenerSession.peer?.fingerprint == diallerIdentity.fingerprint)
		#expect(diallerSession.peer?.fingerprint == listenerIdentity.fingerprint)
		#expect(listenerSession.protocolVersion == .TLSv13)
		#expect(await listenerLog.calls == [diallerIdentity.fingerprint])
		#expect(await diallerLog.calls == [listenerIdentity.fingerprint])
		await sourceFile.close()
		await destinationFile.close()
	}

	@Test("An empty file completes over TLS", .timeLimit(.minutes(1)))
	func emptyFile() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try Data().write(to: source)
		let sourceFile = try TransferFixture.source(source)
		let destinationFile = try TransferFixture.destination(destination)

		let listener = try DCCTransfer(config: SecureFixture.transfer(
			role: .sender, endpoint: SecureFixture.listening,
			configuration: SecureFixture.configuration(), file: sourceFile, fileSize: 0
		))
		let configuration = try SecureFixture.configuration()
		let (local, remote) = try await run(listener: listener) { port in
			DCCTransfer(config: SecureFixture.transfer(
				role: .receiver, endpoint: SecureFixture.dialling(port: port),
				configuration: configuration, file: destinationFile, fileSize: 0
			))
		}

		#expect(local.last.map(TransferFixture.isFinished) == true)
		#expect(remote.last.map(TransferFixture.isFinished) == true)
		#expect(try await destinationFile.size() == 0)
		await sourceFile.close()
		await destinationFile.close()
	}

	@Test("A resumed transfer continues from its offset over TLS", .timeLimit(.minutes(1)))
	func resume() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let payload = TransferFixture.payload(byteCount: 100_003)
		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try payload.write(to: source)
		let sourceFile = try TransferFixture.source(source)
		let destinationFile = try TransferFixture.destination(destination)
		try await destinationFile.write(Data(payload.prefix(37003)), at: 0)
		let size = UInt64(payload.count)

		let sender = try DCCTransfer(config: SecureFixture.transfer(
			role: .sender, endpoint: SecureFixture.listening,
			configuration: SecureFixture.configuration(), file: sourceFile, fileSize: size
		))
		let configuration = try SecureFixture.configuration()
		var local: [DCCTransferEvent] = []
		var remote: Task<[DCCTransferEvent], Never>?
		await sender.start()
		for await event in sender.events {
			local.append(event)
			if case let .listening(port) = event {
				#expect(await sender.commitResumeOffset(37003))
				var config = SecureFixture.transfer(
					role: .receiver, endpoint: SecureFixture.dialling(port: port),
					configuration: configuration, file: destinationFile, fileSize: size
				)
				config.resumeOffset = 37003
				let receiver = DCCTransfer(config: config)
				remote = TransferFixture.collectEvents(from: receiver)
				await receiver.start()
			}
		}

		#expect(local.last.map(TransferFixture.isFinished) == true)
		#expect(await remote?.value.last.map(TransferFixture.isFinished) == true)
		#expect(try Data(contentsOf: destination) == payload)
		await sourceFile.close()
		await destinationFile.close()
	}

	@Test("A rejected peer certificate fails the transfer before any byte is written", .timeLimit(.minutes(1)))
	func rejectedCertificate() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let payload = TransferFixture.payload(byteCount: 64 * 1024)
		let source = directory.appendingPathComponent("source")
		let destination = directory.appendingPathComponent("destination")
		try payload.write(to: source)
		let sourceFile = try TransferFixture.source(source)
		let destinationFile = try TransferFixture.destination(destination)
		let size = UInt64(payload.count)

		let sender = try DCCTransfer(config: SecureFixture.transfer(
			role: .sender, endpoint: SecureFixture.listening,
			configuration: SecureFixture.configuration(), file: sourceFile, fileSize: size
		))
		let refusing = try SecureFixture.configuration { _ in false }
		let (local, remote) = try await run(listener: sender) { port in
			DCCTransfer(config: SecureFixture.transfer(
				role: .receiver, endpoint: SecureFixture.dialling(port: port),
				configuration: refusing, file: destinationFile, fileSize: size
			))
		}

		#expect(remote.last.flatMap(TransferFixture.failure) == .peerCertificateRejected)
		#expect(remote.contains { SecureFixture.session($0) != nil } == false)
		#expect(local.last.flatMap(TransferFixture.failure) != nil)
		#expect(local.contains(where: TransferFixture.isProgress) == false)
		#expect(try await destinationFile.size() == 0)
		await sourceFile.close()
		await destinationFile.close()
	}

	@Test("A verifier that does not answer in time refuses the peer", .timeLimit(.minutes(1)))
	func decisionTimeout() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destinationFile = try TransferFixture.destination(directory.appendingPathComponent("destination"))
		let (port, accepted) = try await TLSLoopbackPeer.listen(
			options: .init(identity: DCCLocalIdentity.generate())
		)
		defer { accepted.cancel() }

		let configuration = try SecureFixture.configuration(decisionTimeout: .milliseconds(200)) { _ in
			try? await Task.sleep(for: .seconds(30))
			return true
		}
		let receiver = DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.dialling(port: port),
			configuration: configuration, file: destinationFile, fileSize: 16
		))
		let events = TransferFixture.collectEvents(from: receiver)
		await receiver.start()

		#expect(await events.value.last.flatMap(TransferFixture.failure) == .peerCertificateRejected)
		await destinationFile.close()
	}

	/** Network.framework calls a TLS server's certificate validator only when
	 the client presents a certificate. The listening side relies on this: a
	 client without one is decided on after the handshake, with no certificate,
	 instead of inside it. */
	@Test(
		"The server's validator runs only for a client certificate",
		.timeLimit(.minutes(1)),
		arguments: [true, false]
	)
	func serverValidatorRunsOnlyForClientCertificates(clientPresentsCertificate: Bool) async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destinationFile = try TransferFixture.destination(directory.appendingPathComponent("destination"))
		let clientIdentity = try clientPresentsCertificate ? DCCLocalIdentity.generate() : nil
		let log = VerifierLog()

		let receiver = try DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.listening,
			configuration: SecureFixture.configuration(log: log), file: destinationFile, fileSize: 4
		))
		await receiver.start()
		var events: [DCCTransferEvent] = []
		var client: Task<Data, Error>?
		for await event in receiver.events {
			events.append(event)
			if case let .listening(port) = event {
				client = Task {
					let connection = try await TLSLoopbackPeer.dial(port: port, options: .init(identity: clientIdentity))
					try await connection.send(Data([1, 2, 3, 4]))
					return try await TLSLoopbackPeer.read(4, from: connection)
				}
			}
		}

		#expect(try await client?.value == DCCTransfer.acknowledgement(for: 4))
		#expect(events.last.map(TransferFixture.isFinished) == true)
		let session = try #require(events.lazy.compactMap(SecureFixture.session).first ?? nil)
		#expect(session.peer?.fingerprint == clientIdentity?.fingerprint)
		#expect(await log.calls == [clientIdentity?.fingerprint])
		await destinationFile.close()
	}

	@Test("A client without a certificate is refused when one is required", .timeLimit(.minutes(1)))
	func certificateRequired() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destinationFile = try TransferFixture.destination(directory.appendingPathComponent("destination"))
		let log = VerifierLog()

		let receiver = try DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.listening,
			configuration: SecureFixture.configuration(requirePeerCertificate: true, log: log),
			file: destinationFile, fileSize: 4
		))
		await receiver.start()
		var events: [DCCTransferEvent] = []
		var client: Task<Void, Error>?
		for await event in receiver.events {
			events.append(event)
			if case let .listening(port) = event {
				client = Task {
					let connection = try await TLSLoopbackPeer.dial(port: port, options: .init())
					try await connection.send(Data([1, 2, 3, 4]))
				}
			}
		}
		_ = await client?.result

		#expect(events.last.flatMap(TransferFixture.failure) == .peerCertificateRequired)
		#expect(await log.calls.isEmpty)
		#expect(try await destinationFile.size() == 0)
		await destinationFile.close()
	}

	@Test("A plain DCC peer reaching a TLS listener fails the handshake", .timeLimit(.minutes(1)))
	func plainPeer() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destinationFile = try TransferFixture.destination(directory.appendingPathComponent("destination"))

		let receiver = try DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.listening,
			configuration: SecureFixture.configuration(), file: destinationFile, fileSize: 64
		))
		await receiver.start()
		var events: [DCCTransferEvent] = []
		var client: Task<Void, Error>?
		for await event in receiver.events {
			events.append(event)
			if case let .listening(port) = event {
				client = Task {
					let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
					let connection = NetworkConnection<TCP>(to: endpoint) { TCP() }
					try await connection.send(Data(repeating: 0x41, count: 64))
					_ = try? await connection.receive(atLeast: 1, atMost: 64)
				}
			}
		}
		client?.cancel()

		let failure = try #require(events.last.flatMap(TransferFixture.failure))
		guard case .tlsHandshakeFailed = failure else {
			Issue.record("expected a handshake failure, got \(failure)")
			return
		}
		#expect(try await destinationFile.size() == 0)
		await destinationFile.close()
	}

	@Test("A peer capped at TLS 1.2 still transfers", .timeLimit(.minutes(1)))
	func olderPeer() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destination = directory.appendingPathComponent("destination")
		let destinationFile = try TransferFixture.destination(destination)
		let payload = TransferFixture.payload(byteCount: 16)
		let serverIdentity = try TLSLoopbackPeer.olderPeerIdentity.get()
		let (port, accepted) = try await TLSLoopbackPeer.listen(
			options: .init(identity: serverIdentity, maximumVersion: .TLSv12), ports: TLSLoopbackPeer.olderPeerPorts
		)
		let server = Task {
			let connection = try await accepted.value
			try await connection.send(payload)
			return try await TLSLoopbackPeer.read(4, from: connection)
		}

		let receiver = try DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.dialling(port: port),
			configuration: SecureFixture.configuration(), file: destinationFile, fileSize: 16
		))
		let events = TransferFixture.collectEvents(from: receiver)
		await receiver.start()
		let collected = await events.value

		#expect(collected.last.map(TransferFixture.isFinished) == true)
		let session = try #require(collected.lazy.compactMap(SecureFixture.session).first ?? nil)
		#expect(session.protocolVersion == .TLSv12)
		#expect(session.peer?.fingerprint == serverIdentity.fingerprint)
		#expect(try await server.value == DCCTransfer.acknowledgement(for: 16))
		#expect(try Data(contentsOf: destination) == payload)
		await destinationFile.close()
	}

	/// Receives 16 bytes from a TLS 1.2 peer listening on `ports`, deciding on
	/// its certificate with `accept`.
	private func receiveFromOlderPeer(
		ports: ClosedRange<UInt16>,
		log: VerifierLog,
		accept: Bool = true
	) async throws -> (port: UInt16, events: [DCCTransferEvent]) {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destinationFile = try TransferFixture.destination(directory.appendingPathComponent("destination"))
		let payload = TransferFixture.payload(byteCount: 16)
		let (port, accepted) = try await TLSLoopbackPeer.listen(
			options: .init(identity: TLSLoopbackPeer.olderPeerIdentity.get(), maximumVersion: .TLSv12), ports: ports
		)
		let server = Task {
			let connection = try await accepted.value
			try await connection.send(payload)
			return try await TLSLoopbackPeer.read(4, from: connection)
		}
		let receiver = try DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.dialling(port: port),
			configuration: SecureFixture.configuration(log: log) { _ in accept }, file: destinationFile, fileSize: 16
		))
		let events = TransferFixture.collectEvents(from: receiver)
		await receiver.start()
		let collected = await events.value
		_ = await server.result
		await destinationFile.close()
		return (port, collected)
	}

	/// A TLS 1.2 session resumed by its identifier skips the certificate
	/// validator; the certificate the session carries is still decided on, and
	/// a refusal still refuses.
	@Test("A resumed TLS 1.2 session is decided on the certificate it carries", .timeLimit(.minutes(1)))
	func resumedSession() async throws {
		let identity = try TLSLoopbackPeer.olderPeerIdentity.get()
		let first = try await receiveFromOlderPeer(ports: TLSLoopbackPeer.resumptionPorts, log: VerifierLog())
		#expect(first.events.last.map(TransferFixture.isFinished) == true)
		let samePort = first.port ... first.port

		let resumedLog = VerifierLog()
		let resumed = try await receiveFromOlderPeer(ports: samePort, log: resumedLog)
		#expect(await resumedLog.calls == [identity.fingerprint])
		#expect(resumed.events.last.map(TransferFixture.isFinished) == true)
		let session = try #require(resumed.events.lazy.compactMap(SecureFixture.session).first ?? nil)
		#expect(session.peer?.fingerprint == identity.fingerprint)

		let refusedLog = VerifierLog()
		let refused = try await receiveFromOlderPeer(ports: samePort, log: refusedLog, accept: false)
		#expect(await refusedLog.calls == [identity.fingerprint])
		let wasRefused = if case .failed(.peerCertificateRejected)? = refused.events.last {
			true
		} else {
			false
		}
		#expect(wasRefused)
	}

	@Test("A TLS peer that overshoots is still cut off at the announced size", .timeLimit(.minutes(1)))
	func oversize() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destination = directory.appendingPathComponent("destination")
		let destinationFile = try TransferFixture.destination(destination)
		let (port, accepted) = try await TLSLoopbackPeer.listen(options: .init(identity: DCCLocalIdentity.generate()))
		let server = Task {
			let connection = try await accepted.value
			try await connection.send(Data(repeating: 0x42, count: 64))
			_ = try? await TLSLoopbackPeer.read(4, from: connection)
		}

		let receiver = try DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.dialling(port: port),
			configuration: SecureFixture.configuration(), file: destinationFile, fileSize: 16
		))
		let events = TransferFixture.collectEvents(from: receiver)
		await receiver.start()

		#expect(await events.value.last.flatMap(TransferFixture.failure) == .oversizedTransfer)
		#expect(try await destinationFile.size() == 16)
		server.cancel()
		await destinationFile.close()
	}

	@Test("Cancelling while the peer is being decided on ends events without a verdict", .timeLimit(.minutes(1)))
	func cancelDuringDecision() async throws {
		let directory = try TransferFixture.makeDirectory()
		defer { TransferFixture.remove(directory) }
		let destinationFile = try TransferFixture.destination(directory.appendingPathComponent("destination"))
		let (port, accepted) = try await TLSLoopbackPeer.listen(options: .init(identity: DCCLocalIdentity.generate()))
		defer { accepted.cancel() }
		let (asked, ask) = AsyncStream<Void>.makeStream()

		let configuration = try SecureFixture.configuration { _ in
			ask.yield()
			try? await Task.sleep(for: .seconds(30))
			return true
		}
		let receiver = DCCTransfer(config: SecureFixture.transfer(
			role: .receiver, endpoint: SecureFixture.dialling(port: port),
			configuration: configuration, file: destinationFile, fileSize: 16
		))
		let events = TransferFixture.collectEvents(from: receiver)
		await receiver.start()
		for await _ in asked {
			break
		}
		await receiver.cancel()

		let collected = await events.value
		#expect(collected.contains { SecureFixture.session($0) != nil || TransferFixture.failure($0) != nil } == false)
		#expect(collected.contains(where: TransferFixture.isFinished) == false)
		await destinationFile.close()
	}

	@Test("A weak certificate is refused without asking the verifier")
	func weakCertificate() async throws {
		let log = VerifierLog()
		let handshake = try DCCTLSHandshake(configuration: SecureFixture.configuration(log: log), role: .client)
		let weak = try #require(DCCPeerCertificate(der: PeerCertificateFixture.rsa(bits: 1024)))

		#expect(await handshake.validate(weak) == false)
		#expect(await handshake.record.refusal == .weakPeerCertificate)
		#expect(await handshake.record.presented == weak)
		#expect(await log.calls.isEmpty)
	}

	@Test("A refusal is reported in place of the TLS alert it caused")
	func failureMapping() async throws {
		let handshake = try DCCTLSHandshake(configuration: SecureFixture.configuration(), role: .server)
		let alert = NWError.tls(errSSLBadCert)

		guard case .tlsHandshakeFailed = await handshake.failure(for: alert) else {
			Issue.record("an alert with no refusal should read as a handshake failure")
			return
		}
		#expect(await handshake.failure(for: DCCTransferError.connectTimeout) == .connectTimeout)
		await handshake.record.refuse(.peerCertificateRejected)
		#expect(await handshake.failure(for: alert) == .peerCertificateRejected)
	}
}
