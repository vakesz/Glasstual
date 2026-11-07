// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** A redirect is server-controlled input, so the account password follows it
 only to a host the network's own server list names. */
@MainActor
@Suite("Session credentials after a redirect")
struct SessionCredentialsRedirectTests {
	private let primary = ServerEndpoint(serverAddress: "irc.example.net")
	private let alternate = ServerEndpoint(serverAddress: "Alt.Example.Net")

	private func redirect(to host: String) -> PendingIRCEndpoint {
		PendingIRCEndpoint(host: host, port: 6697, secured: true, origin: primary, reason: .serverRedirect)
	}

	@Test("A redirect to any configured server keeps that server's credentials")
	func redirectToConfiguredServerIsConfigured() {
		let servers = [primary, alternate]

		#expect(redirect(to: "alt.example.net").credentialEndpoint(among: servers) == alternate)
		#expect(redirect(to: "IRC.EXAMPLE.NET").credentialEndpoint(among: servers) == primary)
	}

	@Test("A redirect to a host the list does not name has no credentials")
	func redirectToUnconfiguredHostHasNone() {
		#expect(redirect(to: "evil.example.org").credentialEndpoint(among: [primary, alternate]) == nil)
	}

	@Test("A /conn to an unconfigured host has no credentials")
	func connectCommandToUnconfiguredHostHasNone() {
		let endpoint = PendingIRCEndpoint(
			host: "elsewhere.example.org", port: 6697, secured: true, origin: primary, reason: .userCommand
		)

		#expect(endpoint.credentialEndpoint(among: [primary, alternate]) == nil)
	}

	@Test("An STS upgrade of the same host keeps its entry")
	func stsUpgradeKeepsItsEntry() {
		let endpoint = PendingIRCEndpoint(
			host: "irc.example.net", port: 6697, secured: true, origin: primary, reason: .stsUpgrade
		)

		#expect(endpoint.credentialEndpoint(among: [primary, alternate]) == primary)
	}

	@Test("The account password is not handed out once credentials are withheld")
	func withheldCredentialsHideTheAccountPassword() {
		let fixture = ChatEnvironmentFixture()
		var config = ServerConfig()
		config.serverList = [primary]
		let session = ServerSession(config: config, environment: fixture.environment)
		session.config.pendingNicknamePassword = .set("hunter2")

		#expect(session.sessionNicknamePassword == "hunter2")

		session.sessionCredentials.withholdsAccountCredentials = true

		#expect(session.sessionNicknamePassword == nil)

		session.sessionCredentials.forget()

		#expect(session.sessionNicknamePassword == "hunter2")
	}
}
