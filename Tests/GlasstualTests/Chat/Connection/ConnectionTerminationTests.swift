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
		session.isConnected = true
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
		session.isConnected = true
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
		session.isConnecting = true
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
