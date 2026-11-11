// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The error a server returns for a refused OAUTHBEARER token (RFC 7628 §3.2.2).
nonisolated struct OAuthBearerFailure: Decodable, Equatable, Sendable {
	let status: String
	let scope: String?
	let openIDConfiguration: String?

	private enum CodingKeys: String, CodingKey {
		case status
		case scope
		case openIDConfiguration = "openid-configuration"
	}
}

/** The client half of SASL OAUTHBEARER (RFC 7628).

 The exchange is one message from each side. The client sends a GS2 header and
 key/value pairs ending in `%x01`; the server either accepts or answers with a
 JSON error, which the client acknowledges with a lone `%x01` before the server
 reports the failure. Channel binding is not offered and the authorization
 identity is left empty: the token names the account. */
nonisolated enum OAuthBearerClient {
	/// The longest token accepted. Real tokens are a few hundred to a couple of
	/// thousand characters; the bound keeps the payload inside one exchange.
	static let maximumTokenLength = 8192

	/// The client's answer to a server error (RFC 7628 §3.2.3).
	static let errorAcknowledgement = Data([0x01])

	/// Whether `token` is an RFC 6750 §2.1 `b64token`:
	/// `1*( ALPHA / DIGIT / "-" / "." / "_" / "~" / "+" / "/" ) *"="`.
	static func isValidToken(_ token: String) -> Bool {
		let scalars = Array(token.unicodeScalars)
		guard scalars.isEmpty == false, scalars.count <= maximumTokenLength else { return false }

		let body = scalars.prefix { $0 != "=" }
		let padding = scalars.dropFirst(body.count)

		guard body.isEmpty == false, padding.allSatisfy({ $0 == "=" }) else { return false }

		return body.allSatisfy { scalar in
			switch scalar {
			case "A" ... "Z", "a" ... "z", "0" ... "9", "-", ".", "_", "~", "+", "/": true
			default: false
			}
		}
	}

	enum ResponseError: Error, Equatable {
		case invalidToken
		case invalidHost
	}

	/// The client's initial response: `n,,` then `host`, `port` and `auth`,
	/// each ended by `%x01`, and a final `%x01`.
	static func initialResponse(token: String, host: String, port: UInt16) throws(ResponseError) -> Data {
		guard isValidToken(token) else { throw .invalidToken }
		guard host.isEmpty == false, host.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F }) else {
			throw .invalidHost
		}

		let separator = "\u{01}"
		let message = "n,," + separator
			+ "host=\(host)" + separator
			+ "port=\(port)" + separator
			+ "auth=Bearer \(token)" + separator
			+ separator

		return Data(message.utf8)
	}

	/// The error a server sent in place of success, or `nil` when the payload
	/// is not the JSON object RFC 7628 describes.
	static func failure(fromServerPayload base64: String) -> OAuthBearerFailure? {
		guard base64.count <= SASLPolicy.maximumPayloadLength,
		      let data = Data(base64Encoded: base64),
		      data.isEmpty == false
		else { return nil }

		return try? JSONDecoder().decode(OAuthBearerFailure.self, from: data)
	}
}
