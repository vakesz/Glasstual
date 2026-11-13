// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Secure DCC CHAT over loopback")
struct DCCSecureChatLoopbackTests {
	private static let portRange: ClosedRange<UInt16> = 49880 ... 50080

	private static func socket(
		_ endpoint: DCCEndpoint,
		configuration: DCCTLSConfiguration,
		maximumLineLength: Int = 16 * 1024
	) -> DirectChatSocket {
		DirectChatSocket(config: DirectChatSocket.Config(
			endpoint: endpoint,
			security: .tls(configuration),
			maximumLineLength: maximumLineLength,
			sendTimeout: .seconds(20)
		))
	}

	private enum Step: Equatable {
		case connected(DCCCertificateFingerprint?)
		case line(String)
		case closed(DCCTransferError?)
	}

	/// One side's events as steps: all of them once the side has finished,
	/// and each one as it happens so the test can wait for it.
	private struct Recording {
		let steps: Task<[Step], Never>
		let live: AsyncStream<Step>

		/// Waits for the first step `matches` accepts.
		func next(where matches: (Step) -> Bool) async -> Step? {
			for await step in live where matches(step) {
				return step
			}
			return nil
		}
	}

	/// Records a side's events in order, acknowledging each batch of lines.
	private static func record(_ socket: DirectChatSocket) -> Recording {
		let events = socket.events
		let (live, continuation) = AsyncStream<Step>.makeStream()
		let steps = Task {
			defer { continuation.finish() }
			var steps: [Step] = []
			for await event in events {
				var new: [Step] = []
				switch event {
				case .listening:
					break
				case let .connected(session):
					new = [.connected(session?.peer?.fingerprint)]
				case let .lines(batch, acknowledged):
					new = batch.map { .line(ChatFixture.decode($0)) }
					acknowledged.finish()
				case let .closed(error):
					new = [.closed(error)]
				}
				steps.append(contentsOf: new)
				new.forEach { continuation.yield($0) }
			}
			return steps
		}
		return Recording(steps: steps, live: live)
	}

	private static func isConnected(_ step: Step) -> Bool {
		if case .connected = step {
			true
		} else {
			false
		}
	}

	private static func isLine(_ step: Step) -> Bool {
		if case .line = step {
			true
		} else {
			false
		}
	}

	@Test("Lines cross TLS in both directions after the peer is verified", .timeLimit(.minutes(1)))
	func linesBothWays() async throws {
		let listenerIdentity = try DCCLocalIdentity.generate()
		let diallerIdentity = try DCCLocalIdentity.generate()
		let listening = try Self.socket(
			.listen(portRange: Self.portRange),
			configuration: SecureFixture.configuration(identity: listenerIdentity)
		)
		await listening.start()
		let port = try #require(await ChatFixture.listeningPort(of: listening))
		let dialling = try Self.socket(
			.connect(host: ChatFixture.loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			configuration: SecureFixture.configuration(identity: diallerIdentity)
		)
		let listened = Self.record(listening)
		let dialled = Self.record(dialling)
		await dialling.start()

		#expect(await listened.next(where: Self.isConnected) != nil)
		#expect(await dialled.next(where: Self.isConnected) != nil)
		try await dialling.send(Data("hello from the dialler".utf8))
		try await listening.send(Data("hello from the listener".utf8))
		#expect(await listened.next(where: Self.isLine) == .line("hello from the dialler"))
		#expect(await dialled.next(where: Self.isLine) == .line("hello from the listener"))
		await dialling.close()

		let listenerSteps = await listened.steps.value
		#expect(Array(listenerSteps.prefix(2)) == [
			.connected(diallerIdentity.fingerprint), .line("hello from the dialler"),
		])
		#expect(listenerSteps.last == .closed(nil))
		await listening.close()
		#expect(await dialled.steps.value.prefix(2) == [
			.connected(listenerIdentity.fingerprint), .line("hello from the listener"),
		])
	}

	@Test("A TLS peer that never sends a newline is cut off at the cap", .timeLimit(.minutes(1)))
	func lineCap() async throws {
		let listening = try Self.socket(
			.listen(portRange: Self.portRange),
			configuration: SecureFixture.configuration(),
			maximumLineLength: 4096
		)
		await listening.start()
		let port = try #require(await ChatFixture.listeningPort(of: listening))
		let dialling = try Self.socket(
			.connect(host: ChatFixture.loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			configuration: SecureFixture.configuration()
		)
		let listened = Self.record(listening)
		let dialled = Self.record(dialling)
		await dialling.start()
		#expect(await dialled.next(where: Self.isConnected) != nil)
		try await dialling.write(Data(repeating: UInt8(ascii: "a"), count: 8192))

		let steps = await listened.steps.value
		#expect(steps.last == .closed(.badParameter))
		#expect(steps.contains(where: Self.isLine) == false)
		await dialling.close()
	}
}
