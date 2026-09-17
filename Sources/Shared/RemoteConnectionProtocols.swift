// Copyright (c) 2017, 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
import Security

typealias SecureConnectionInformationReceiver = @Sendable (SecureConnectionInformation) -> Void

/// Commands the application sends to the isolated connection host.
///
/// `Sendable` because both ends already are: what the application holds is an
/// NSXPC proxy, and what the service exports is a forwarding shim whose only
/// state is the queue it hands the commands to. Saying so lets a caller pass
/// the connection between tasks without the compiler having to take it on
/// trust.
@objc(RCMConnectionManagerServerProtocol)
nonisolated protocol RemoteConnectionServerProtocol: AnyObject, Sendable { // nonisolated: xpc-shim
	@objc(openWithConfig:)
	func open(with config: ConnectionConfigEnvelope)

	@objc(close)
	func close()

	/// The caller includes the IRC line terminator in `data`.
	@objc(sendData:)
	func send(_ data: Data)

	@objc(sendData:bypassQueue:)
	func send(_ data: Data, bypassQueue: Bool)

	/// The receiver is an XPC reply block: the service answers it once, and it
	/// may answer after this call has returned.
	@objc(exportSecureConnectionInformation:)
	func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver)

	@objc(enforceFloodControl)
	func enforceFloodControl()

	@objc(clearSendQueue)
	func clearSendQueue()

	/// Held until the connection ends: the host balances it when the
	/// application detaches, so there is no enabling half to call.
	@objc(disableAppNap)
	func disableAppNap()

	/// Held until the connection ends, balanced the same way as ``disableAppNap()``.
	@objc(disableSuddenTermination)
	func disableSuddenTermination()
}

/// Events the isolated connection host sends back to the application.
@objc(RCMConnectionManagerClientProtocol)
nonisolated protocol RemoteConnectionClientProtocol: AnyObject, Sendable { // nonisolated: xpc-shim
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

	/** The complete lines one read from the server produced, in wire order.

	 `acknowledge` is an XPC reply block, and it is the flow control: the host
	 reads nothing more from the socket until the application has handled these
	 lines and answered. A server that sends faster than the application can
	 keep up is slowed by TCP rather than filling a queue between the two
	 processes, so no amount of traffic can overrun the application. */
	@objc(ircConnectionDidReceiveLines:acknowledge:)
	func ircConnectionDidReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void)

	@objc(ircConnectionRequestInsecureCertificateTrust:)
	func ircConnectionRequestInsecureCertificateTrust(_ response: @escaping TrustDecisionHandler)

	@objc(ircConnectionWillSendData:)
	func ircConnectionWillSend(_ data: Data)

	@objc(ircConnectionDidSendData)
	func ircConnectionDidSendData()
}

/// The interfaces both ends of the connection host speak.
///
/// Built in one place because a collection argument is only decoded for the
/// classes its interface names: an interface assembled by hand on either side
/// without them refuses every received line.
nonisolated enum RemoteConnectionInterface {
	/// What the application calls on the host.
	static func server() -> NSXPCInterface {
		NSXPCInterface(with: RemoteConnectionServerProtocol.self)
	}

	/// What the host calls on the application.
	static func client() -> NSXPCInterface {
		let interface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		interface.setClasses(
			NSSet(objects: NSArray.self, NSData.self) as? Set<AnyHashable> ?? [],
			for: #selector(RemoteConnectionClientProtocol.ircConnectionDidReceive(_:acknowledge:)),
			argumentIndex: 0,
			ofReply: false
		)
		return interface
	}
}

/** The code-signing requirement the connection host holds its peer to.

 An application's embedded XPC service is only published to that application,
 so this is defence in depth rather than the only gate: the host still refuses
 a connection from anything but the application it ships in, signed with the
 very certificate the host itself was signed with. Pinning the certificate
 rather than a team keeps the rule the same for development, Developer ID and
 App Store signatures, all of which sign the application and its services
 together. */
nonisolated enum RemoteConnectionPeerRequirement {
	/// The requirement text for `applicationIdentifier` signed with
	/// `leafCertificate`, the DER bytes of the signing certificate.
	static func requirement(applicationIdentifier: String, leafCertificate: Data) -> String {
		/* Requirement hash constants are the certificate's SHA-1, the only
		 digest the requirement language accepts for `certificate leaf = H`. */
		let digest = Insecure.SHA1.hash(data: leafCertificate).map { String(format: "%02x", $0) }.joined()
		return "identifier \"\(applicationIdentifier)\" and anchor apple generic and certificate leaf = H\"\(digest)\""
	}

	/// The requirement for `applicationIdentifier`, pinned to the certificate
	/// the running process is signed with. `nil` when the process carries no
	/// certificate — an unsigned or ad-hoc build, which has nothing to pin.
	static func requirement(forCurrentProcessAnd applicationIdentifier: String) -> String? {
		var code: SecCode?
		var staticCode: SecStaticCode?
		var information: CFDictionary?
		guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
		      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
		      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
		      let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
		      let leaf = certificates.first
		else {
			return nil
		}

		return requirement(
			applicationIdentifier: applicationIdentifier,
			leafCertificate: SecCertificateCopyData(leaf) as Data
		)
	}
}
