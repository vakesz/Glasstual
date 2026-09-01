/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// The values that replaced loose XPC argument lists have to survive the
/// archiver that carries them across the process boundary.
struct SecureConnectionInformationTests {
	private func roundTripped(_ value: SecureConnectionInformation) throws -> SecureConnectionInformation {
		let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
		let decoded = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: SecureConnectionInformation.self,
			from: data
		)

		return try #require(decoded)
	}

	@Test
	func survivesSecureCoding() throws {
		let chain = [Data([0x01, 0x02]), Data([0x03])]
		let original = SecureConnectionInformation(
			policyName: "irc.example.net",
			protocolVersion: .TLSv13,
			cipherSuite: .AES_256_GCM_SHA384,
			certificateChain: chain,
			trustFailureDescription: "expired"
		)

		let decoded = try roundTripped(original)

		#expect(decoded.policyName == "irc.example.net")
		#expect(decoded.protocolVersion == .TLSv13)
		#expect(decoded.cipherSuite == .AES_256_GCM_SHA384)
		#expect(decoded.certificateChain == chain)
		#expect(decoded.trustFailureDescription == "expired")
	}

	/// A connection that never negotiated TLS used to be five arguments whose
	/// only signal was a nil in the first position.
	@Test
	func survivesSecureCodingWithNothingNegotiated() throws {
		let decoded = try roundTripped(.none)

		#expect(decoded.policyName == nil)
		#expect(decoded.trustFailureDescription == nil)
		#expect(decoded.certificateChain.isEmpty)
		#expect(decoded.protocolVersion == tlsProtocolVersionUnknown)
		#expect(decoded.cipherSuite == tlsCipherSuiteUnknown)
	}

	@Test
	func declaresSecureCodingSupport() {
		#expect(SecureConnectionInformation.supportsSecureCoding)
	}
}

/// One notification name per event: a duplicate raw string means two
/// declarations that can drift, and an inline literal means a name nobody can
/// find by searching for the constant.
@MainActor
struct IRCProtocolNotificationNameTests {
	private static let moduleDirectory = "Sources/App/Protocol"

	private static func moduleSources() -> [URL]? {
		var directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent() // GlasstualTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // repository root
		directory.append(path: moduleDirectory)

		guard let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: nil
		) else {
			return nil
		}

		return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
	}

	@Test
	func declaresEachNotificationNameOnce() throws {
		let sources = try #require(Self.moduleSources(), "the IRCProtocol sources are not where the test expects")
		try #require(sources.isEmpty == false)

		let literal = /"([A-Za-z0-9._\/]*Notification)"/
		var occurrences: [String: [String]] = [:]

		for source in sources {
			let contents = try String(contentsOf: source, encoding: .utf8)

			for match in contents.matches(of: literal) {
				occurrences[String(match.output.1), default: []].append(source.lastPathComponent)
			}
		}

		let duplicated = occurrences.filter { $0.value.count > 1 }

		#expect(duplicated.isEmpty, "notification names spelled out more than once: \(duplicated)")
	}
}
