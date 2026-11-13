// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Endpoint selection")
struct EndpointSelectionTests {
	private let first = ServerEndpoint(serverAddress: "one.example.net", serverPort: 6697, prefersSecuredConnection: true)
	private let second = ServerEndpoint(serverAddress: "two.example.net", serverPort: 6667)

	private var servers: [ServerEndpoint] {
		[first, second]
	}

	private func explicit(_ host: String, reason: PendingIRCEndpoint.Reason = .userCommand) -> PendingIRCEndpoint {
		PendingIRCEndpoint(host: host, port: 7000, secured: true, origin: nil, reason: reason)
	}

	@Test("The rotation starts at the first server and wraps")
	func rotationWraps() {
		var selection = EndpointSelection()

		let hosts = (0 ..< 3).map { _ in selection.take(from: servers, retrying: nil).host }

		#expect(hosts == ["one.example.net", "two.example.net", "one.example.net"])
		#expect(selection.lastIndex == 0)
		#expect(selection.current == first)
	}

	@Test("A retry dials the server it names and moves the rotation there")
	func retryPinsTheIndex() {
		var selection = EndpointSelection()
		_ = selection.take(from: servers, retrying: nil)

		let retried = selection.take(from: servers, retrying: first.uniqueIdentifier)
		let next = selection.take(from: servers, retrying: nil)

		#expect(retried.host == "one.example.net")
		#expect(retried.port == 6697)
		#expect(retried.secured)
		#expect(next.host == "two.example.net")
		#expect(selection.lastIndex == 1)
	}

	@Test("An explicit valid host is dialled as it is and leaves the rotation")
	func explicitHostSkipsTheRotation() {
		var selection = EndpointSelection()
		_ = selection.take(from: servers, retrying: nil)
		selection.pending = explicit("other.example.org")

		let target = selection.take(from: servers, retrying: nil)

		#expect(target == EndpointSelection.Target(host: "other.example.org", port: 7000, secured: true, reason: .userCommand))
		#expect(selection.lastIndex == 0)
		#expect(selection.pending == nil)
		#expect(selection.current == nil)
	}

	@Test("An explicit host that is a configured server takes that entry")
	func explicitConfiguredHostSelectsItsEntry() {
		var selection = EndpointSelection()
		selection.pending = explicit("TWO.example.net")

		_ = selection.take(from: servers, retrying: nil)

		#expect(selection.current == second)
		#expect(selection.lastIndex == nil)
	}

	@Test("An invalid explicit host falls back to the rotation and keeps its reason")
	func invalidExplicitHostFallsBack() {
		var selection = EndpointSelection()
		selection.pending = explicit("not a host", reason: .stsUpgrade)

		let target = selection.take(from: servers, retrying: nil)

		#expect(target.host == "one.example.net")
		#expect(target.reason == .stsUpgrade)
		#expect(selection.lastIndex == 0)
		#expect(selection.current == first)
	}
}
