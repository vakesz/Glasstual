/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Error codes in `SCRAMClient.errorDomain`.
public enum SCRAMClientErrorCode: Int {
	case invalidState = 1
	case malformedServerMessage
	case nonceMismatch
	case iterationCountTooLow
	case serverRejected
	case serverSignatureMismatch
	case keyDerivationFailed
	case iterationCountTooHigh
}

/// Client side of SASL SCRAM-SHA-256 (RFC 5802, RFC 7677).
///
/// The caller drives the exchange: send `clientFirstMessage`, pass the
/// server's first message to `clientFinalMessage(forServerFirstMessage:)`
/// and send the result, then pass the server's final message to
/// `verifyServerFinalMessage(_:)`. The object is single use.
///
/// Channel binding is not offered (`n,,`). Passwords are used as typed;
/// SASLprep is not applied, which matches what IRC servers do.
///
/// The exchange is driven from `IRCClientNegotiation`, which is main-actor
/// state, so the client's state machine belongs to the same domain. Only the
/// PBKDF2 derivation leaves it, and that is a pure function.
@MainActor
public final class SCRAMClient: NSObject {
	public enum State: Int {
		case initial
		case sentClientFirst
		case sentClientFinal
		case authenticated
		case failed
	}

	public static let errorDomain = "TLOSCRAMClientErrorDomain"

	/// The mechanism name as advertised in `sasl=` values and on the wire.
	public static let mechanismName = "SCRAM-SHA-256"

	private static let gs2Header = "n,,"
	private static let minimumIterationCount = 4096

	/// Upper bound on the server supplied `i=`. PBKDF2 is deliberately
	/// expensive, so an unbounded count is a denial of service; 600000 is
	/// well above what any deployed IRC server asks for.
	private static let maximumIterationCount = 600_000

	public private(set) var state: State = .initial

	private let username: String
	private let password: String
	private let clientNonce: String

	private var clientFirstMessageBare = ""
	private var serverSignature = Data()

	/// Creates a client with a fresh random nonce.
	public convenience init(username: String, password: String) {
		self.init(username: username, password: password, clientNonce: SCRAMClient.makeNonce())
	}

	/// Creates a client with a caller supplied nonce. Only tests should
	/// pick their own nonce.
	public init(username: String, password: String, clientNonce: String) {
		self.username = username
		self.password = password
		self.clientNonce = clientNonce
	}

	// MARK: - Messages

	/// `n,,n=<user>,r=<nonce>`. Moves the state to `sentClientFirst`.
	public var clientFirstMessage: String {
		if state == .initial {
			clientFirstMessageBare = "n=\(SCRAMClient.escapeSASLName(username)),r=\(clientNonce)"

			state = .sentClientFirst
		}

		return SCRAMClient.gs2Header + clientFirstMessageBare
	}

	/// Parses `r=,s=,i=` and returns `c=,r=,p=`. Throws on a malformed
	/// message, a nonce that does not begin with ours, or an iteration
	/// count below the RFC 7677 minimum.
	public func clientFinalMessage(forServerFirstMessage serverFirst: String) throws -> String {
		let challenge = try parseServerFirstMessage(serverFirst)

		guard let saltedPassword = SCRAMClient.pbkdf2(
			password: password,
			salt: challenge.salt,
			iterations: challenge.iterations
		) else {
			throw fail(.keyDerivationFailed, "PBKDF2 failed")
		}

		return completeClientFinalMessage(
			serverFirst: serverFirst,
			challenge: challenge,
			saltedPassword: saltedPassword
		)
	}

	/// Same exchange step as `clientFinalMessage(forServerFirstMessage:)`,
	/// but the PBKDF2 derivation runs off the caller's actor so a large
	/// server supplied iteration count cannot block the main thread.
	public func clientFinalMessage(forServerFirstMessage serverFirst: String) async throws -> String {
		let challenge = try parseServerFirstMessage(serverFirst)

		guard let saltedPassword = await SCRAMClient.pbkdf2Offloaded(
			password: password,
			salt: challenge.salt,
			iterations: challenge.iterations
		) else {
			throw fail(.keyDerivationFailed, "PBKDF2 failed")
		}

		return completeClientFinalMessage(
			serverFirst: serverFirst,
			challenge: challenge,
			saltedPassword: saltedPassword
		)
	}

	private struct ServerFirstChallenge {
		let combinedNonce: String
		let salt: Data
		let iterations: Int
	}

	private func parseServerFirstMessage(_ serverFirst: String) throws -> ServerFirstChallenge {
		guard state == .sentClientFirst else {
			throw fail(.invalidState, "SCRAM exchange is not waiting for the server's first message")
		}

		let attributes = SCRAMClient.parseAttributes(serverFirst)

		if let serverError = attributes["e"] {
			throw fail(.serverRejected, serverError)
		}

		guard let combinedNonce = attributes["r"],
		      let saltBase64 = attributes["s"],
		      let salt = Data(base64Encoded: saltBase64),
		      let iterationString = attributes["i"],
		      let iterations = Int(iterationString), iterations > 0
		else {
			throw fail(.malformedServerMessage, "Server first message is missing r=, s= or i=")
		}

		guard combinedNonce.hasPrefix(clientNonce), combinedNonce.count > clientNonce.count else {
			throw fail(.nonceMismatch, "Server nonce does not begin with the client nonce")
		}

		guard iterations >= SCRAMClient.minimumIterationCount else {
			throw fail(.iterationCountTooLow, "Server asked for \(iterations) iterations")
		}

		guard iterations <= SCRAMClient.maximumIterationCount else {
			throw fail(.iterationCountTooHigh, "Server asked for \(iterations) iterations")
		}

		return ServerFirstChallenge(combinedNonce: combinedNonce, salt: salt, iterations: iterations)
	}

	private func completeClientFinalMessage(
		serverFirst: String,
		challenge: ServerFirstChallenge,
		saltedPassword: Data
	) -> String {
		let clientKey = SCRAMClient.hmac(key: saltedPassword, message: Data("Client Key".utf8))
		let storedKey = Data(SHA256.hash(data: clientKey))
		let serverKey = SCRAMClient.hmac(key: saltedPassword, message: Data("Server Key".utf8))

		let channelBinding = Data(SCRAMClient.gs2Header.utf8).base64EncodedString()
		let clientFinalWithoutProof = "c=\(channelBinding),r=\(challenge.combinedNonce)"

		let authMessage = [clientFirstMessageBare, serverFirst, clientFinalWithoutProof].joined(separator: ",")
		let authMessageData = Data(authMessage.utf8)

		let clientSignature = SCRAMClient.hmac(key: storedKey, message: authMessageData)
		let clientProof = Data(zip(clientKey, clientSignature).map { $0 ^ $1 })

		serverSignature = SCRAMClient.hmac(key: serverKey, message: authMessageData)

		state = .sentClientFinal

		return clientFinalWithoutProof + ",p=" + clientProof.base64EncodedString()
	}

	/// Checks `v=` against the expected server signature. A mismatch means
	/// the server does not know the password and must not be trusted.
	public func verifyServerFinalMessage(_ serverFinal: String) throws {
		guard state == .sentClientFinal else {
			throw fail(.invalidState, "SCRAM exchange is not waiting for the server's final message")
		}

		let attributes = SCRAMClient.parseAttributes(serverFinal)

		if let serverError = attributes["e"] {
			throw fail(.serverRejected, serverError)
		}

		guard let verifier = attributes["v"], let received = Data(base64Encoded: verifier) else {
			throw fail(.malformedServerMessage, "Server final message is missing v=")
		}

		guard SCRAMClient.constantTimeEquals(received, serverSignature) else {
			throw fail(.serverSignatureMismatch, "Server signature does not match")
		}

		state = .authenticated
	}

	// MARK: - Helpers

	private func fail(_ code: SCRAMClientErrorCode, _ description: String) -> NSError {
		state = .failed

		return NSError(
			domain: SCRAMClient.errorDomain,
			code: code.rawValue,
			userInfo: [NSLocalizedDescriptionKey: description]
		)
	}

	static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
		guard lhs.count == rhs.count, lhs.isEmpty == false else {
			return false
		}

		var difference: UInt8 = 0

		for (left, right) in zip(lhs, rhs) {
			difference |= left ^ right
		}

		return difference == 0
	}

	/// Splits `a=1,b=2` into a dictionary. Values may contain `=`; only
	/// the first one separates the attribute from its value.
	static func parseAttributes(_ message: String) -> [String: String] {
		var attributes: [String: String] = [:]

		for component in message.split(separator: ",", omittingEmptySubsequences: true) {
			guard let separator = component.firstIndex(of: "=") else {
				continue
			}

			let name = String(component[..<separator])
			let value = String(component[component.index(after: separator)...])

			if name.count == 1 {
				attributes[name] = value
			}
		}

		return attributes
	}

	/// RFC 5802 section 5.1: `=` becomes `=3D` and `,` becomes `=2C`.
	static func escapeSASLName(_ name: String) -> String {
		name.replacingOccurrences(of: "=", with: "=3D").replacingOccurrences(of: ",", with: "=2C")
	}

	static func makeNonce() -> String {
		var bytes = [UInt8](repeating: 0, count: 24)

		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

		if status != errSecSuccess {
			for index in bytes.indices {
				bytes[index] = UInt8.random(in: 0 ... 255)
			}
		}

		/* The nonce must be printable ASCII without commas. Base64 fits. */
		return Data(bytes).base64EncodedString()
	}

	static func hmac(key: Data, message: Data) -> Data {
		Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
	}

	/// `pbkdf2(password:salt:iterations:)` on a background executor.
	@concurrent
	static func pbkdf2Offloaded(password: String, salt: Data, iterations: Int) async -> Data? {
		pbkdf2(password: password, salt: salt, iterations: iterations)
	}

	/// PBKDF2-HMAC-SHA256 producing a 32 byte key. Pure, so the offloaded
	/// wrapper above can call it from the cooperative pool.
	nonisolated static func pbkdf2(password: String, salt: Data, iterations: Int) -> Data? { // nonisolated: pure
		guard let roundCount = UInt32(exactly: iterations) else {
			return nil
		}

		let passwordBytes = password.utf8.map { CChar(bitPattern: $0) }
		let saltBytes = [UInt8](salt)

		var derived = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

		let status = passwordBytes.withUnsafeBufferPointer { passwordPointer in
			CCKeyDerivationPBKDF(
				CCPBKDFAlgorithm(kCCPBKDF2),
				passwordPointer.baseAddress,
				passwordBytes.count,
				saltBytes,
				saltBytes.count,
				CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
				roundCount,
				&derived,
				derived.count
			)
		}

		guard status == kCCSuccess else {
			return nil
		}

		return Data(derived)
	}
}
