// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** An inline image is fetched from the reader's Mac on the word of whoever
 wrote the line, so it must not be a way to reach what only that Mac can. */
@MainActor
@Suite("Inline image host policy")
struct InlineImageHostPolicyTests {
	@Test("Literal loopback, private, link-local and unique-local addresses are refused",
	      arguments: [
	      	"127.0.0.1", "10.1.2.3", "192.168.0.1", "172.16.0.9", "169.254.169.254", "0.0.0.0",
	      	"::1", "fe80::1", "fd00::1", "::ffff:127.0.0.1", "0:0:0:0:0:0:0:1",
	      ])
	func privateLiteralsAreRefused(host: String) {
		#expect(InlineImageHostPolicy.verdict(forHost: host) == .refused)
	}

	@Test("Names that are local by construction are refused",
	      arguments: [
	      	"localhost", "LOCALHOST", "app.localhost", "printer.local", "nas", "router.lan",
	      	"host.internal", "127.1", "0x7f.1", "2130706433", "localhost.",
	      ])
	func localNamesAreRefused(host: String) {
		#expect(InlineImageHostPolicy.verdict(forHost: host) == .refused)
	}

	private nonisolated static let remoteAddressCases: [(String?, Bool)] = [
		("127.0.0.1", false), ("10.0.0.5", false), ("169.254.169.254", false),
		("fe80::1%en0", false), ("::1", false), ("not-an-address", false),
		("8.8.8.8", true), ("2606:4700:4700::1111", true), (nil, true), ("", true),
	]

	@Test("A connection that reached a private address is refused, a public or unreported one is not",
	      arguments: remoteAddressCases)
	func remoteAddressDecision(address: String?, allowed: Bool) {
		#expect(InlineImageHostPolicy.permitsRemoteAddress(address) == allowed)
	}

	@Test("A public literal is allowed without a lookup")
	func publicLiteralIsAllowed() {
		#expect(InlineImageHostPolicy.verdict(forHost: "8.8.8.8") == .allowed)
		#expect(InlineImageHostPolicy.verdict(forHost: "2606:4700:4700::1111") == .allowed)
	}

	@Test("A public-looking name waits for its addresses")
	func publicNameNeedsResolution() {
		#expect(InlineImageHostPolicy.verdict(forHost: "images.example.org") == .needsResolution)
		#expect(InlineImageHostPolicy.verdict(forHost: nil) == .refused)
		#expect(InlineImageHostPolicy.verdict(forHost: "") == .refused)
	}

	@Test("A name that resolves to a private address is refused")
	func resolvedPrivateAddressIsRefused() async throws {
		let url = try #require(URL(string: "https://rebind.example.org/a.png"))
		let resolver = InlineImageHostResolver { _ in ["93.184.216.34", "10.0.0.5"] }

		#expect(await InlineImageHostPolicy.permits(url, resolver: resolver) == false)
	}

	@Test("A name that resolves to a zoned link-local address is refused")
	func resolvedZonedAddressIsRefused() async throws {
		let url = try #require(URL(string: "https://zone.example.org/a.png"))
		let resolver = InlineImageHostResolver { _ in ["fe80::1%en0"] }

		#expect(await InlineImageHostPolicy.permits(url, resolver: resolver) == false)
	}

	@Test("A name that resolves only to public addresses is allowed")
	func resolvedPublicAddressIsAllowed() async throws {
		let url = try #require(URL(string: "https://images.example.org/a.png"))
		let resolver = InlineImageHostResolver { _ in ["8.8.8.8", "2606:4700:4700::1111"] }

		#expect(await InlineImageHostPolicy.permits(url, resolver: resolver))
	}

	@Test("A lookup that outlives the deadline is refused, not waited for", .timeLimit(.minutes(1)))
	func slowLookupIsRefused() async throws {
		let url = try #require(URL(string: "https://slow.example.org/a.png"))
		let resolver = InlineImageHostResolver { _ in
			try? await Task.sleep(for: .seconds(60))
			return ["8.8.8.8"]
		}

		#expect(await InlineImageHostPolicy.permits(url, resolver: resolver, deadline: .milliseconds(50)) == false)
	}

	@Test("A cancelled caller stops waiting for its lookup", .timeLimit(.minutes(1)))
	func cancelledLookupReturnsPromptly() async throws {
		let url = try #require(URL(string: "https://slow.example.org/a.png"))
		let resolver = InlineImageHostResolver { _ in
			try? await Task.sleep(for: .seconds(60))
			return ["8.8.8.8"]
		}
		let task = Task { await InlineImageHostPolicy.permits(url, resolver: resolver) }
		task.cancel()

		#expect(await task.value == false)
	}

	@Test("Callers asking for one name share a single lookup", .timeLimit(.minutes(1)))
	func callersShareOneLookup() async throws {
		let probe = LookupProbe()
		let resolver = InlineImageHostResolver { host in await probe.lookup(host) }
		let url = try #require(URL(string: "https://shared.example.org/a.png"))
		let callers = (0 ..< 5).map { _ in
			Task { await InlineImageHostPolicy.permits(url, resolver: resolver) }
		}
		try await Eventually.untilResolved("the lookup to start") { await probe.callCount == 1 }
		await probe.release()
		for caller in callers {
			#expect(await caller.value)
		}
		#expect(await probe.callCount == 1)
	}

	@Test("A lookup past its caller's deadline keeps its place, and the next caller joins it", .timeLimit(.minutes(1)))
	func abandonedLookupIsJoinedNotRestarted() async throws {
		let probe = LookupProbe()
		let resolver = InlineImageHostResolver { host in await probe.lookup(host) }
		let url = try #require(URL(string: "https://stuck.example.org/a.png"))

		#expect(await InlineImageHostPolicy.permits(url, resolver: resolver, deadline: .milliseconds(30)) == false)
		#expect(await InlineImageHostPolicy.permits(url, resolver: resolver, deadline: .milliseconds(30)) == false)
		#expect(await probe.callCount == 1)
		await probe.release()
	}

	@Test("One caller giving up leaves the others waiting on the same lookup", .timeLimit(.minutes(1)))
	func cancellingOneWaiterSparesTheRest() async throws {
		let probe = LookupProbe()
		let resolver = InlineImageHostResolver { host in await probe.lookup(host) }
		let url = try #require(URL(string: "https://shared.example.org/a.png"))
		let leaving = Task { await InlineImageHostPolicy.permits(url, resolver: resolver) }
		let staying = Task { await InlineImageHostPolicy.permits(url, resolver: resolver) }
		try await Eventually.untilResolved("the lookup to start") { await probe.callCount == 1 }
		leaving.cancel()

		#expect(await leaving.value == false)
		await probe.release()
		#expect(await staying.value)
	}

	@Test("A name past the in-flight bound is refused at once without a lookup", .timeLimit(.minutes(1)))
	func boundIsHitFailsClosed() async throws {
		let probe = LookupProbe()
		let resolver = InlineImageHostResolver(addresses: { host in await probe.lookup(host) }, maximumInFlight: 2)
		let first = try #require(URL(string: "https://one.example.org/a.png"))
		let second = try #require(URL(string: "https://two.example.org/a.png"))
		let third = try #require(URL(string: "https://three.example.org/a.png"))
		let held = [first, second].map { url in
			Task { await InlineImageHostPolicy.permits(url, resolver: resolver) }
		}
		try await Eventually.untilResolved("both lookups to start") { await probe.callCount == 2 }

		#expect(await InlineImageHostPolicy.permits(third, resolver: resolver, deadline: .seconds(30)) == false)
		#expect(await probe.callCount == 2)

		await probe.release()
		for task in held {
			#expect(await task.value)
		}
		// A finished lookup frees its place.
		#expect(await InlineImageHostPolicy.permits(third, resolver: resolver))
	}

	@Test("A download from a private host is refused before any request", .timeLimit(.minutes(1)))
	func downloadRefusesPrivateHost() async throws {
		let url = try #require(URL(string: "http://127.0.0.1:8080/a.png"))

		await #expect(throws: InlineImageError.self) {
			try await InlineImageTransfer.download(url, limits: InlineImageLimits(), protocolClasses: [])
		}
	}

	@Test("The loader reports a private host without queuing work")
	func loaderRefusesPrivateHost() throws {
		let budget = InlineImageBudget()
		let loader = InlineImageLoader(budget: budget, protocolClasses: [InlineImageTestProtocol.self])
		let url = try #require(URL(string: "https://192.168.1.1/a.png"))
		var failure: InlineImageError?

		let token = loader.load(url: url, viewIdentifier: "view", lineNumber: "line", linkIdentifier: "link") { result in
			if case let .failure(error) = result {
				failure = error as? InlineImageError
			}
		}

		#expect(token == nil)
		#expect(failure == .hostNotAllowed)
		#expect(budget.entryCount == 0)
	}
}

/// A resolver stand-in that counts the lookups it is asked for and holds each
/// one until released.
private actor LookupProbe {
	private(set) var callCount = 0
	private var isReleased = false
	private var waiting: [CheckedContinuation<Void, Never>] = []

	func lookup(_: String) async -> [String] {
		callCount += 1
		if !isReleased {
			await withCheckedContinuation { waiting.append($0) }
		}
		return ["8.8.8.8"]
	}

	func release() {
		isReleased = true
		let continuations = waiting
		waiting = []
		for continuation in continuations {
			continuation.resume()
		}
	}
}
