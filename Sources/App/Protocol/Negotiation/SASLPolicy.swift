// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** What the session will speak for SASL, and how much of it.

 Pure decisions over the mechanisms and the payload: which mechanisms are on
 offer from this side, which one to try next, how long to wait for the server's
 half, and how the payload is cut into `AUTHENTICATE` lines. */
enum SASLPolicy {
	/// Ceiling on the reassembled `AUTHENTICATE` payload. Every mechanism the
	/// session supports fits in a fraction of this; without it a server can
	/// grow the buffer 400 characters at a time forever.
	static let maximumPayloadLength = 16384

	/** The mechanisms the session can speak, in the order it tries them.

	 - Parameter sendsPasswordInClear: Whether the connection may carry the
	   password itself. `PLAIN` sends it as typed, so it is left out where the
	   answer is no; SCRAM proves knowledge of the password without sending it
	   and stays available. */
	static func supportedMechanisms(
		hasClientCertificate: Bool,
		externalMechanismDisabled: Bool,
		hasPassword: Bool,
		sendsPasswordInClear: Bool = true,
		preferredMechanism: String?
	) -> [String] {
		var mechanisms: [String] = []

		if hasClientCertificate, externalMechanismDisabled == false {
			mechanisms.append("EXTERNAL")
		}

		if hasPassword {
			mechanisms.append(SCRAMClient.mechanismName)
			if sendsPasswordInClear {
				mechanisms.append("PLAIN")
			}
		}

		guard let preferredMechanism, let preferredIndex = mechanisms.firstIndex(where: {
			$0.caseInsensitiveCompare(preferredMechanism) == .orderedSame
		}) else {
			return mechanisms
		}

		let preferred = mechanisms.remove(at: preferredIndex)
		mechanisms.insert(preferred, at: 0)

		return mechanisms
	}

	static func nextMechanism(
		from supported: [String],
		offered: [String],
		tried: [String]
	) -> String? {
		supported.first { mechanism in
			let wasTried = tried.contains {
				$0.caseInsensitiveCompare(mechanism) == .orderedSame
			}
			let wasOffered = offered.isEmpty || offered.contains {
				$0.caseInsensitiveCompare(mechanism) == .orderedSame
			}

			return wasTried == false && wasOffered
		}
	}

	/// How long the session waits for the server's half of a SASL exchange.
	static let timeout: TimeInterval = 30

	static func wireChunks(for payload: String) -> [String] {
		let encoded = Data(payload.utf8).base64EncodedString()

		guard encoded.isEmpty == false else {
			return ["+"]
		}

		var chunks: [String] = []
		var start = encoded.startIndex

		while start < encoded.endIndex {
			let end = encoded.index(start, offsetBy: 400, limitedBy: encoded.endIndex) ?? encoded.endIndex
			chunks.append(String(encoded[start ..< end]))
			start = end
		}

		if chunks.last?.count == 400 {
			chunks.append("+")
		}

		return chunks
	}
}
