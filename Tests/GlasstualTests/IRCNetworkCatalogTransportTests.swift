/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

@testable import Glasstual
import Testing

/// The bundled catalogue decides what port a first-time connection uses, so the
/// pairing of `serverPort` and `prefersSecuredConnection` is a real contract:
/// a network that says it prefers TLS but points at the cleartext port connects
/// in the clear, and one on a TLS port with the flag off fails its handshake.
@Suite("Bundled network transport defaults")
struct IRCNetworkCatalogTransportTests {
	/// Ports an ircd conventionally serves TLS on.
	private static let securePorts: Set<UInt16> = [6697, 7000, 7070, 9999]

	/// The conventional cleartext port.
	private static let cleartextPort: UInt16 = 6667

	@Test("A network preferring a secured connection never points at a cleartext port")
	func securedNetworksUseSecurePorts() {
		let networks = NetworkList().listOfNetworks
		#expect(networks.isEmpty == false)

		for network in networks where network.prefersSecuredConnection {
			#expect(
				network.serverPort != Self.cleartextPort,
				"\(network.networkName) prefers TLS but defaults to \(network.serverPort)"
			)
		}
	}

	@Test("A network on a TLS port asks for a secured connection")
	func securePortsImplySecuredConnection() {
		for network in NetworkList().listOfNetworks
			where Self.securePorts.contains(network.serverPort)
		{
			#expect(
				network.prefersSecuredConnection,
				"\(network.networkName) defaults to \(network.serverPort) without preferring TLS"
			)
		}
	}

	/// Probed against each network's advertised TLS endpoint. These four are the
	/// ones whose certificate chain verifies against the system trust store, so
	/// they connect without a trust prompt; the rest of the cleartext entries
	/// either serve no TLS or serve a self-signed or expired certificate.
	@Test(
		"Networks verified to serve TLS default to it",
		arguments: ["2600net", "GeekShed", "IRCnet", "Slashnet"]
	)
	func verifiedNetworksDefaultToTLS(_ name: String) throws {
		let network = try #require(NetworkList().network(named: name))

		#expect(network.serverPort == 6697)
		#expect(network.prefersSecuredConnection)
	}
}
