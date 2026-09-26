// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Synchronization
import Testing

@MainActor
struct CertificateTrustRequestTests {
	private final class Presenter {
		var decision: ((Bool) -> Void)?
		var presentations = 0
		var dismissals = 0

		func present(_: SecureConnectionInformation, decided: @escaping (Bool) -> Void) -> (() -> Void)? {
			presentations += 1
			decision = decided
			return { self.dismissals += 1 }
		}
	}

	@Test("Cancellation before export refuses once and ignores the late certificate")
	func cancelBeforePresentation() {
		let presenter = Presenter()
		var decisions: [Bool] = []
		let request = CertificateTrustRequest(present: presenter.present) { decisions.append($0) }
		request.cancel()
		request.present(.none)
		request.cancel()
		#expect(decisions == [false])
		#expect(presenter.presentations == 0)
		#expect(presenter.dismissals == 0)
	}

	@Test("Cancellation dismisses only its own panel and ignores a late approval")
	func cancelVisiblePresentation() {
		let firstPresenter = Presenter()
		let secondPresenter = Presenter()
		var decisions: [Bool] = []
		let first = CertificateTrustRequest(present: firstPresenter.present) { decisions.append($0) }
		let second = CertificateTrustRequest(present: secondPresenter.present, decided: { _ in })
		first.present(.none)
		second.present(.none)
		first.cancel()
		firstPresenter.decision?(true)
		#expect(decisions == [false])
		#expect(firstPresenter.dismissals == 1)
		#expect(secondPresenter.dismissals == 0)
		second.cancel()
	}

	@Test("A user decision completes once", arguments: [false, true])
	func completesOnce(trusted: Bool) {
		let presenter = Presenter()
		var decisions: [Bool] = []
		let request = CertificateTrustRequest(present: presenter.present) { decisions.append($0) }
		request.present(.none)
		request.present(.none)
		presenter.decision?(trusted)
		presenter.decision?(!trusted)
		request.cancel()
		#expect(decisions == [trusted])
		#expect(presenter.presentations == 1)
		#expect(presenter.dismissals == 1)
	}

	@Test("An unavailable presenter refuses trust")
	func presentationFailure() {
		var decisions: [Bool] = []
		let request = CertificateTrustRequest(present: { _, _ in nil }, decided: { decisions.append($0) })
		request.present(.none)
		request.cancel()
		#expect(decisions == [false])
	}

	@Test("A synchronous decision dismisses the returned panel without answering twice")
	func synchronousDecision() {
		var decisions: [Bool] = []
		var dismissals = 0
		let request = CertificateTrustRequest(present: { _, decide in
			decide(true)
			return { dismissals += 1 }
		}, decided: { decisions.append($0) })
		request.present(.none)
		#expect(decisions == [true])
		#expect(dismissals == 1)
	}

	@Test("Releasing an unanswered request dismisses it and refuses trust")
	func releaseUnansweredRequest() {
		let presenter = Presenter()
		var decisions: [Bool] = []
		var request: CertificateTrustRequest? = CertificateTrustRequest(present: presenter.present) { decisions.append($0) }
		request?.present(.none)
		request = nil
		#expect(decisions == [false])
		#expect(presenter.dismissals == 1)
		presenter.decision?(true)
		#expect(decisions == [false])
	}

	@Test("An unrelated connection cannot cancel the application's pending certificate prompt")
	func unrelatedConnectionClose() throws {
		let panel = CertificatePresenter()
		var decisions: [Bool] = []
		let pending = try #require(panel.beginTrustRequest { decisions.append($0) })
		let session = ServerSession(config: ServerConfig(), environment: ChatEnvironment(
			settings: .current(), services: ChatServices(certificates: panel)
		))
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		connection.close()
		#expect(decisions.isEmpty)
		#expect(panel.beginTrustRequest(decided: { _ in }) == nil)
		pending.cancel()
		#expect(decisions == [false])
		let next = try #require(panel.beginTrustRequest(decided: { _ in }))
		next.cancel()
	}

	@Test("A missing XPC connection refuses trust and releases the prompt reservation")
	func missingConnection() throws {
		let presenter = CertificatePresenter()
		let session = ServerSession(config: ServerConfig(), environment: ChatEnvironment(
			settings: .current(), services: ChatServices(certificates: presenter)
		))
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		defer { session.socket = nil }
		let decisions = Mutex<[Bool]>([])
		connection.requestCertificateTrust { trusted in decisions.withLock { $0.append(trusted) } }
		#expect(decisions.withLock { $0 } == [false])
		#expect(connection.certificateTrustRequest == nil)
		let next = try #require(presenter.beginTrustRequest(decided: { _ in }))
		next.cancel()
	}

	@Test("Malformed certificate data releases the application's prompt reservation")
	func malformedCertificate() throws {
		let panel = CertificatePresenter()
		var decisions: [Bool] = []
		let pending = try #require(panel.beginTrustRequest { decisions.append($0) })
		pending.present(.none)
		#expect(decisions == [false])
		let next = try #require(panel.beginTrustRequest(decided: { _ in }))
		next.cancel()
	}
}
