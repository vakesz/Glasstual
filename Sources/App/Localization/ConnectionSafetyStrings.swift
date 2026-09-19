// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Semantic access to `ConnectionSafety.xcstrings`.

 These are the notices the connection layer prints when it refuses something a
 peer or a server asked for — a direct chat offer pointing at an address the
 session will not dial, a download the destination volume has no room for, a
 SASL exchange the server never answered. They are grouped by the refusal
 rather than by the feature because each of them has to say plainly what was
 refused and why; a bare failure reads as the session being broken. */
nonisolated enum ConnectionSafetyStrings {
	enum DirectChat {
		static func refusedAddress(sender: String, address: String) -> String {
			String(localized: .ConnectionSafety.directChatOfferRefusedAddress(sender, address))
		}

		static func requestBody(sender: String, address: String) -> String {
			String(localized: .ConnectionSafety.directChatRequestWithAddress(sender, address))
		}
	}

	enum FileTransfer {
		static func refusedBecauseCrowded(sender: String) -> String {
			String(localized: .ConnectionSafety.fileTransferOfferRefusedCrowded(sender))
		}
	}

	enum Wire {
		static func lineTruncated(sentByteCount: Int, limit: Int) -> String {
			String(localized: .ConnectionSafety.outgoingLineTruncated(sentByteCount, limit))
		}
	}

	enum Credentials {
		static var withheldOverPlaintext: String {
			String(localized: .ConnectionSafety.credentialsWithheldOverPlaintext)
		}
	}

	enum SASL {
		static var credentialsContainNullCharacter: String {
			String(localized: .ConnectionSafety.saslCredentialsContainANullCharacter)
		}

		static var timedOut: String {
			String(localized: .ConnectionSafety.saslAuthenticationTimedOut)
		}
	}
}
