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

		static var lineRefusedByEncoding: String {
			String(localized: .ConnectionSafety.outgoingLineRefusedEncoding)
		}

		static var unprintedLinesHeldBack: String {
			String(localized: .ConnectionSafety.outgoingUnprintedLinesHeldBack)
		}
	}

	enum Credentials {
		static var withheldOverPlaintext: String {
			String(localized: .ConnectionSafety.credentialsWithheldOverPlaintext)
		}

		static func withheldFromUnconfiguredHost(_ host: String) -> String {
			String(localized: .ConnectionSafety.credentialsWithheldUnconfiguredHost(host))
		}

		static var withheldUnverifiedCertificate: String {
			String(localized: .ConnectionSafety.credentialsWithheldUnverifiedCertificate)
		}

		static var unverifiedCertificateTitle: String {
			String(localized: .ConnectionSafety.credentialsUnverifiedCertificateTitle)
		}

		static func unverifiedCertificateBody(host: String) -> String {
			String(localized: .ConnectionSafety.credentialsUnverifiedCertificateBody(host))
		}

		static func changedCertificateBody(host: String) -> String {
			String(localized: .ConnectionSafety.credentialsChangedCertificateBody(host))
		}

		static var send: String {
			String(localized: .ConnectionSafety.credentialsUnverifiedCertificateSend)
		}

		static var dontSend: String {
			String(localized: .ConnectionSafety.credentialsUnverifiedCertificateDontSend)
		}
	}

	enum SASL {
		static var credentialsContainNullCharacter: String {
			String(localized: .ConnectionSafety.saslCredentialsContainANullCharacter)
		}

		static var ecdsaKeyUnavailable: String {
			String(localized: .ConnectionSafety.saslEcdsaKeyUnavailable)
		}

		static var ecdsaChallengeInvalid: String {
			String(localized: .ConnectionSafety.saslEcdsaChallengeInvalid)
		}

		static func oauthTokenRejected(status: String) -> String {
			String(localized: .ConnectionSafety.saslOauthTokenRejected(status))
		}

		static var oauthTokenRejectedWithoutStatus: String {
			String(localized: .ConnectionSafety.saslOauthTokenRejectedWithoutStatus)
		}

		static var oauthRequiresTLS: String {
			String(localized: .ConnectionSafety.saslOauthRequiresTls)
		}

		static var oauthExchangeInvalid: String {
			String(localized: .ConnectionSafety.saslOauthExchangeInvalid)
		}

		static var timedOut: String {
			String(localized: .ConnectionSafety.saslAuthenticationTimedOut)
		}
	}
}
