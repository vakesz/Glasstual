// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("Connection terminal diagnostics", .timeLimit(.minutes(1)))
struct ConnectionTerminationTests {
	@Test("A host failure captures the state before reset and reports only once")
	func hostFailurePreservesTerminalState() async throws {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connected)
		session.disconnectType = .reachabilityChange
		var config = ConnectionConfig()
		config.diagnostics = ConnectionDiagnostics()
		let recorder = TerminationRecorder()
		let connection = Connection(config: config, onSession: session, closeClock: .continuous,
		                            recordTermination: recorder.record)
		session.socket = connection
		let receiver = connection.callbackReceiver
		receiver.didSecureConnection(withProtocolType: .TLSv12, cipherSuite: tlsCipherSuiteUnknown)
		receiver.didCloseReadStream()
		let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET),
		                    userInfo: [NSLocalizedDescriptionKey: "private message text"])
		receiver.didDisconnect(withError: error)
		receiver.didDisconnect(withError: error)

		let report = try await recorder.next()
		connection.close()
		connection.beginCloseDeadline()

		#expect(recorder.reports.count == 1)
		#expect(report.attemptIdentifier == config.diagnostics?.identifier)
		#expect(report.elapsed >= 0)
		#expect(report.trigger == .hostDisconnect)
		#expect(report.phase == .secured)
		#expect(report.receivedEOF)
		#expect(!report.localCloseRequested)
		#expect(report.disconnectMode == .reachabilityChange)
		#expect(report.errorDomain == NSPOSIXErrorDomain)
		#expect(report.errorCode == Int(ECONNRESET))
		#expect(connection.isSecured == false)
		#expect(connection.EOFReceived == false)
	}

	@Test("A local close is distinguished from a peer failure")
	func localCloseIsExplicit() {
		let session = TestServerSession()
		let recorder = TerminationRecorder()
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: .continuous,
		                            recordTermination: recorder.record)
		session.socket = connection

		connection.close()
		connection.close()

		#expect(recorder.reports.count == 1)
		#expect(recorder.reports.first?.trigger == .localClose)
		#expect(recorder.reports.first?.phase == .requested)
		#expect(recorder.reports.first?.localCloseRequested == true)
		#expect(recorder.reports.first?.errorDomain == nil)
	}

	@Test("A certificate error retains its effective disconnect mode and startup phase")
	func certificateErrorIsClassified() async throws {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.startup.authentication = .confirmed
		let recorder = TerminationRecorder()
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: .continuous,
		                            recordTermination: recorder.record)
		session.socket = connection
		connection.callbackReceiver.didDisconnect(withError: NSError(
			domain: connectionErrorDomain,
			code: Int(ConnectionErrorCode.badCertificate.rawValue)
		))

		let report = try await recorder.next()

		#expect(report.phase == .authenticated)
		#expect(report.disconnectMode == .badCertificate)
		#expect(report.errorCode == Int(ConnectionErrorCode.badCertificate.rawValue))
	}

	@Test("An unavailable service records startup failure exactly once")
	func unavailableServiceIsRecorded() async throws {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connecting)
		let recorder = TerminationRecorder()
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: .continuous,
		                            recordTermination: recorder.record,
		                            makeService: { NSXPCConnection(serviceName: "test.glasstual.unavailable-service") })
		session.socket = connection
		connection.open()

		let report = try await recorder.next()
		connection.close()

		#expect(recorder.reports.count == 1)
		#expect([.serviceFailure, .serviceInvalidated, .serviceInterrupted].contains(report.trigger))
		#expect(report.phase == .connecting)
		#expect(report.errorDomain != nil)
		#expect(!report.localCloseRequested)
		#expect(session.socket == nil)
	}

	@Test("Shutdown closes a late connection callback before registration or credentials", arguments: [false, true])
	func shutdownRefusesLateStartupCallback(secured: Bool) async throws {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connecting)
		session.reconnect.isEnabled = true
		session.server = ServerEndpoint(serverAddress: "irc.example.test", pendingServerPassword: .set("private-password"))
		let recorder = TerminationRecorder()
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: .continuous,
		                            recordTermination: recorder.record)
		session.socket = connection
		session.fixture.applicationState.applicationIsTerminating = true
		let receiver = connection.callbackReceiver

		if secured {
			receiver.didSecureConnection(withProtocolType: .TLSv13, cipherSuite: tlsCipherSuiteUnknown)
		} else {
			receiver.didConnect(toHost: "127.0.0.1")
		}
		_ = try await recorder.next()

		#expect(session.sentCapabilityCommands.count == 0)
		#expect(session.sentLines.count == 0)
		#expect(session.socket == nil)
		#expect(!connection.isConnected)
		#expect(!connection.isSecured)
		#expect(!session.reconnect.timer.isActive)
		#expect(recorder.reports.count == 1)
		#expect(recorder.reports.first?.localCloseRequested == true)
	}

	@Test("Shutdown during capability negotiation discards and acknowledges the pending read")
	func shutdownRefusesRegistrationRead() async throws {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connected)
		session.reconnect.isEnabled = true
		let recorder = TerminationRecorder()
		let connection = Connection(config: ConnectionConfig(), onSession: session, closeClock: .continuous,
		                            recordTermination: recorder.record)
		session.socket = connection
		session.fixture.applicationState.applicationIsTerminating = true
		let (acknowledgements, acknowledge) = AsyncStream<Void>.makeStream()
		connection.callbackReceiver.didReceive([Data("CAP * LS :sasl=PLAIN".utf8)]) {
			acknowledge.yield()
			acknowledge.finish()
		}
		_ = try await recorder.next()
		var iterator = acknowledgements.makeAsyncIterator()
		#expect(await iterator.next() != nil)
		#expect(session.sentCapabilityCommands.count == 0)
		#expect(session.sentLines.count == 0)
		#expect(session.processedMessages.isEmpty)
		#expect(session.socket == nil)
		#expect(!session.reconnect.timer.isActive)
	}

	@Test("Shutdown refuses opening the service before session teardown")
	func shutdownRefusesServiceStartup() {
		let session = TestServerSession()
		var serviceCreated = false
		let connection = Connection(
			config: ConnectionConfig(), onSession: session, closeClock: .continuous,
			makeService: {
				serviceCreated = true
				return NSXPCConnection(serviceName: "test.glasstual.unavailable-service")
			}
		)
		session.socket = connection
		defer { session.socket = nil }
		session.fixture.applicationState.applicationIsTerminating = true

		connection.open()

		#expect(!serviceCreated)
		#expect(!connection.isConnecting)
	}
}

@MainActor
private final class TerminationRecorder {
	private(set) var reports: [ConnectionTermination] = []
	private let stream: AsyncStream<ConnectionTermination>
	private let continuation: AsyncStream<ConnectionTermination>.Continuation

	init() {
		(stream, continuation) = AsyncStream.makeStream()
	}

	func record(_ report: ConnectionTermination) {
		reports.append(report)
		continuation.yield(report)
	}

	func next() async throws -> ConnectionTermination {
		let deadline = Task { [continuation] in
			do { try await Task.sleep(for: .seconds(5)) } catch { return }
			continuation.finish()
		}
		defer { deadline.cancel() }
		var iterator = stream.makeAsyncIterator()
		return try #require(await iterator.next(), "The connection did not report its terminal transition")
	}
}
