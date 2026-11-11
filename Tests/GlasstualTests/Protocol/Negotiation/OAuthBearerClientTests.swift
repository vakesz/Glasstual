// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("SASL OAUTHBEARER client")
struct OAuthBearerClientTests {
	@Test("The initial response matches the RFC 7628 layout")
	func initialResponseMatchesVector() throws {
		let response = try OAuthBearerClient.initialResponse(token: "vF9dft4qmT", host: "irc.example.net", port: 6697)
		#expect(response.base64EncodedString()
			== "biwsAWhvc3Q9aXJjLmV4YW1wbGUubmV0AXBvcnQ9NjY5NwFhdXRoPUJlYXJlciB2RjlkZnQ0cW1UAQE=")
	}

	@Test("A host that could split the key/value list is refused")
	func hostWithSeparatorIsRefused() {
		#expect(throws: OAuthBearerClient.ResponseError.invalidHost) {
			try OAuthBearerClient.initialResponse(token: "abc", host: "irc\u{01}example", port: 6697)
		}
		#expect(throws: OAuthBearerClient.ResponseError.invalidToken) {
			try OAuthBearerClient.initialResponse(token: "a b", host: "irc.example.net", port: 6697)
		}
	}

	@Test("Tokens are RFC 6750 b64tokens", arguments: [
		("abc-._~+/XYZ019", true),
		("abc==", true),
		("abc=d", false),
		("=", false),
		("", false),
		("a b", false),
		("a\u{01}b", false),
		("tökén", false),
		(String(repeating: "a", count: OAuthBearerClient.maximumTokenLength + 1), false),
	])
	func tokenCharacterSet(_ token: String, _ isValid: Bool) {
		#expect(OAuthBearerClient.isValidToken(token) == isValid)
	}

	@Test("A JSON error decodes its status, scope and discovery document")
	func errorDecodes() throws {
		let payload = Data("""
		{"status": "invalid_token", "scope": "irc", "openid-configuration": "https://example.com/.well-known/openid-configuration"}
		""".utf8).base64EncodedString()

		let failure = try #require(OAuthBearerClient.failure(fromServerPayload: payload))
		#expect(failure.status == "invalid_token")
		#expect(failure.scope == "irc")
		#expect(failure.openIDConfiguration == "https://example.com/.well-known/openid-configuration")
	}

	@Test("A payload that is not the JSON error decodes as nothing", arguments: [
		Data("not json".utf8).base64EncodedString(),
		Data("{\"scope\": \"irc\"}".utf8).base64EncodedString(),
		"%%%",
		"",
		String(repeating: "A", count: SASLPolicy.maximumPayloadLength + 4),
	])
	func malformedErrorIsNil(_ payload: String) {
		#expect(OAuthBearerClient.failure(fromServerPayload: payload) == nil)
	}
}
