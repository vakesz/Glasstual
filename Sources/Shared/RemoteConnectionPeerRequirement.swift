// Copyright (c) 2017, 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation
import Security

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
