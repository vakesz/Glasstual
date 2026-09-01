/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Security
import Testing

/// The trust panel is handed a DER chain, not a `SecTrust`: the connection
/// service exports the chain, and the app rebuilds the trust object on the main
/// actor so no Security.framework value crosses an isolation boundary.
@Suite("Trust from an exported certificate chain")
nonisolated struct TrustPanelCertificateChainTests { // nonisolated: value
	@Test("A chain of one DER certificate rebuilds into a SecTrust for the named policy")
	func chainRebuildsIntoTrust() throws {
		let certificate = try Self.fixtureCertificate()

		let trust = try #require(SecureTransportSupport.trust(
			fromCertificateChain: [certificate],
			policyName: "irc.example.net"
		))

		#expect(SecureTransportSupport.policyName(in: trust) == "irc.example.net")
	}

	@Test("The rebuilt trust carries back exactly the bytes it was given")
	func rebuiltTrustRoundTripsTheChain() async throws {
		let certificate = try Self.fixtureCertificate()

		let exported = try await Task.detached {
			let trust = try #require(SecureTransportSupport.trust(
				fromCertificateChain: [certificate],
				policyName: "irc.example.net"
			))

			return try #require(SecureTransportSupport.certificates(in: trust))
		}.value

		#expect(exported == [certificate])
	}

	@Test("An empty chain builds nothing rather than an empty trust")
	func emptyChainBuildsNothing() {
		#expect(SecureTransportSupport.trust(fromCertificateChain: [], policyName: "irc.example.net") == nil)
	}

	@Test("Bytes that are not a certificate build nothing")
	func garbageChainBuildsNothing() {
		let garbage = Data([0x30, 0x00, 0xFF, 0xFF])

		#expect(SecureTransportSupport.trust(fromCertificateChain: [garbage], policyName: "irc.example.net") == nil)
	}

	/// A self-signed certificate for `irc.example.net`, in DER, as the service
	/// would export it. It is never validated here -- only rebuilt -- so its
	/// expiry does not matter to the test.
	private static func fixtureCertificate() throws -> Data {
		let base64 =
			"MIIDFTCCAf2gAwIBAgIUYn23QCZQYwFCwMYDGTqD2oIepWkwDQYJKoZIhvcNAQELBQAwGjEYMBYGA1UEAwwPaXJjLmV4YW1w" +
			"bGUubmV0MB4XDTI2MDgyOTA1NDkzN1oXDTM2MDgyNjA1NDkzN1owGjEYMBYGA1UEAwwPaXJjLmV4YW1wbGUubmV0MIIBIjAN" +
			"BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAok874Y4ipLpmQDK4/kKWopoqcWihRJXrQxWo0YOEXXMtO6HsLt7VV7jEd89k" +
			"UH4tK2dBTszSCVmJasXm6OuNYDqxTxQQaNsT1dsDugnVsLiOC7NnvRVkqOUPbhdiqJ/VjDcyMGewajKaLeJO6DcfWka/GfeY" +
			"budCW9aEfQcGt7/mgcMdPpHLs7BmI6JK4HK6tXJvq4sfQjleeSIxV74fObZZYaahnVwDqUb3z6gboMxuU1B/VIjNLUMeLLmX" +
			"uYjwbjEhGmW86t/sBvmcFHiOfqf3KGWX/DUTw2CQFNVEZA/hEzo/FpaWicHx8snzoCP8OzJNNik2Af1SKdc/Dek2iwIDAQAB" +
			"o1MwUTAdBgNVHQ4EFgQUq3l4LTB2MnB1NFHUjGVlk7dChAcwHwYDVR0jBBgwFoAUq3l4LTB2MnB1NFHUjGVlk7dChAcwDwYD" +
			"VR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAP8LTj4RXx2Fnf5a9IeytP4y6kjsTmjIYsEUHqoYCNFu5BJmt3ZEB" +
			"ehCcspxUWRrS05NgchwxVvyGpLEWCQB+VNWS31oraSddBXdhMQnq2uZcsLTfS38K0KG2MIEn2B3XSS4kDoZ8OvPc9XvnB+vI" +
			"7rFJ0qSOYj6/uS1mzEUHM24KXtzBc61IInMegHOnKVSE2+K8q8V5BlC7O8+N3xPn92Xlx4pHOngP8OJ8SyvsTywkzWZngsf1" +
			"JchHEqtqTlAXAycwCa8Q1fI1JfDJahCN17GXXMAOlkMkU1rsGtrlEMthNHLZR60sE1cloh24q2t+wi0vMLjrqEaqK/wcABbD" +
			"3A=="

		return try #require(Data(base64Encoded: base64))
	}
}
