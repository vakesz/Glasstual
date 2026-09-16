/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 Codeux Software, LLC & respective contributors.
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

import Foundation
import Security

/// Everything the transport reports, in the order it happened.
///
/// The socket publishes the results of its async Network.framework operations
/// here, and the host reads them from one `AsyncStream` in wire order.
enum SocketEvent: Sendable {
	case willConnectToProxy(host: String, port: UInt16)
	case connected(host: String?)
	case secured(protocolVersion: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	/// The complete lines of one read. The transport reads no further until
	/// `acknowledged` finishes, which the host hands to the application's reply.
	case received([Data], acknowledged: AsyncStream<Void>.Continuation)
	case willSend(Data)
	case didSend
	case closedReadStream
	case disconnected(ConnectionError?)
}

/// What the service learned about the peer's certificate chain.
///
/// Produced and consumed by the socket actor's async TLS validation path. The
/// `SecTrust` it came from never escapes the validator.
struct TLSTrustExport: Sendable {
	var policyName: String?
	var certificateChain: [Data] = []

	/// Why the system did not trust the chain. nil when it did, or when the
	/// chain has not been evaluated yet.
	var failureDescription: String?
}

struct TLSTrustEvaluation: Sendable {
	var export: TLSTrustExport
	var isRecoverableFailure: Bool
}
