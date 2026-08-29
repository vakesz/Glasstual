/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2020 Codeux Software, LLC & respective contributors.
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

import CocoaExtensions
import Foundation
import Security

typealias SecureConnectionInformationReceiver = @Sendable (SecureConnectionInformation) -> Void

/// Commands the application sends to the isolated connection host.
@objc(RCMConnectionManagerServerProtocol)
nonisolated protocol RemoteConnectionServerProtocol: AnyObject { // nonisolated: xpc-shim
	@objc(openWithConfig:)
	func open(with config: ConnectionConfigEnvelope)

	@objc(close)
	func close()

	/// The caller includes the IRC line terminator in `data`.
	@objc(sendData:)
	func send(_ data: Data)

	@objc(sendData:bypassQueue:)
	func send(_ data: Data, bypassQueue: Bool)

	@objc(exportSecureConnectionInformation:)
	func exportSecureConnectionInformation(_ receiver: SecureConnectionInformationReceiver)

	@objc(enforceFloodControl)
	func enforceFloodControl()

	@objc(clearSendQueue)
	func clearSendQueue()

	@objc(enableAppNap)
	func enableAppNap()

	@objc(disableAppNap)
	func disableAppNap()

	@objc(enableSuddenTermination)
	func enableSuddenTermination()

	@objc(disableSuddenTermination)
	func disableSuddenTermination()
}

/// Events the isolated connection host sends back to the application.
@objc(RCMConnectionManagerClientProtocol)
nonisolated protocol RemoteConnectionClientProtocol: AnyObject { // nonisolated: xpc-shim
	@objc(ircConnectionWillConnectToProxy:port:)
	func ircConnectionWillConnect(toProxy proxyHost: String, port proxyPort: UInt16)

	@objc(ircConnectionDidConnectToHost:)
	func ircConnectionDidConnect(toHost host: String?)

	@objc(ircConnectionDidSecureConnectionWithProtocolType:cipherSuite:)
	func ircConnectionDidSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	)

	@objc(ircConnectionDidCloseReadStream)
	func ircConnectionDidCloseReadStream()

	@objc(ircConnectionDidDisconnectWithError:)
	func ircConnectionDidDisconnectWithError(_ disconnectError: Error?)

	@objc(ircConnectionDidReceiveData:)
	func ircConnectionDidReceive(_ data: Data)

	@objc(ircConnectionRequestInsecureCertificateTrust:)
	func ircConnectionRequestInsecureCertificateTrust(_ response: @escaping TrustDecisionHandler)

	@objc(ircConnectionWillSendData:)
	func ircConnectionWillSend(_ data: Data)

	@objc(ircConnectionDidSendData)
	func ircConnectionDidSendData()
}
