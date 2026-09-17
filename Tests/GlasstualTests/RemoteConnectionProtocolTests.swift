// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Security
import Testing

@MainActor
@Suite("Remote connection protocol")
struct RemoteConnectionProtocolTests {
	/// The configuration is a value type now, so it crosses the connection
	/// inside an `NSSecureCoding` envelope.
	@Test("Opening a connection allows the configuration envelope across XPC")
	func openAllowsTheConnectionConfigurationEnvelope() {
		let interface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		let allowedClasses = interface.classes(
			for: #selector((any RemoteConnectionServerProtocol).open(with:)),
			argumentIndex: 0,
			ofReply: false
		)

		#expect((allowedClasses as NSSet).contains(ConnectionConfigEnvelope.self))
	}

	/// A collection argument decodes only the classes its interface names, so
	/// an interface without them would refuse every line the host forwards.
	@Test("The client interface accepts a read's lines across XPC")
	func clientInterfaceAllowsLineBatches() {
		let allowedClasses = RemoteConnectionInterface.client().classes(
			for: #selector((any RemoteConnectionClientProtocol).ircConnectionDidReceive(_:acknowledge:)),
			argumentIndex: 0,
			ofReply: false
		) as NSSet

		#expect(allowedClasses.contains(NSArray.self))
		#expect(allowedClasses.contains(NSData.self))
	}

	@Test("The peer requirement names the application and pins the signing certificate")
	func peerRequirementText() {
		let requirement = RemoteConnectionPeerRequirement.requirement(
			applicationIdentifier: "com.example.app",
			leafCertificate: Data("certificate".utf8)
		)

		#expect(requirement ==
			#"identifier "com.example.app" and anchor apple generic and certificate leaf = H"735ad571c189d7ba84464bf4a9f1d2280175b128""#)
	}

	/// The host builds its requirement from its own signature, and the
	/// application it ships in is signed with the same certificate — which the
	/// test host is too. It has to admit that application and nothing else.
	@Test("The requirement built from this process's signature admits this application only", arguments: [true, false])
	func peerRequirementMatchesTheSigningApplication(_ namesThisApplication: Bool) throws {
		let identifier = try #require(Bundle.main.bundleIdentifier)
		let text = try #require(RemoteConnectionPeerRequirement.requirement(
			forCurrentProcessAnd: namesThisApplication ? identifier : identifier + ".impostor"
		))
		var requirement: SecRequirement?
		try #require(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
		var code: SecCode?
		try #require(SecCodeCopySelf([], &code) == errSecSuccess)

		let runningCode = try #require(code)
		let signingRequirement = try #require(requirement)
		let status = SecCodeCheckValidity(runningCode, [], signingRequirement)

		#expect((status == errSecSuccess) == namesThisApplication)
	}
}
