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

struct InlineContentServicePreferencesTests {
	private let sample = InlineContentServicePreferences(
		maximumFilesize: 7,
		scalingWidth: 640,
		maximumHeight: 480,
		limitToBasics: true,
		limitBasicsToFiles: false,
		limitNaughtyContent: true,
		limitUnsafeContent: false,
		checkEverything: true,
		allowsCleartextHTTP: false
	)

	@Test
	func survivesSecureCoding() throws {
		let data = try NSKeyedArchiver.archivedData(withRootObject: sample, requiringSecureCoding: true)
		let unarchived = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: InlineContentServicePreferences.self,
			from: data
		)
		let decoded = try #require(unarchived)

		#expect(decoded.maximumFilesize == 7)
		#expect(decoded.scalingWidth == 640)
		#expect(decoded.maximumHeight == 480)
		#expect(decoded.limitToBasics)
		#expect(decoded.limitBasicsToFiles == false)
		#expect(decoded.limitNaughtyContent)
		#expect(decoded.limitUnsafeContent == false)
		#expect(decoded.checkEverything)
		#expect(decoded.allowsCleartextHTTP == false)
	}

	/// The service reads these through `TextualPreferences`, so the domain has
	/// to be keyed by the same names the app writes.
	@Test
	func producesARegistrationDomainKeyedByThePreferenceNames() {
		let domain = sample.registrationDomain

		#expect(domain.count == 9)
		#expect(domain[Preferences.InlineMedia.maximumFilesize.name] as? UInt == 7)
		#expect(domain[Preferences.InlineMedia.scalingWidth.name] as? UInt == 640)
		#expect(domain[Preferences.InlineMedia.checkEverything.name] as? Bool == true)
	}

	/// The whole point of the type: it carries exactly the keys the service
	/// needs, not the app's entire registration domain.
	@Test
	func coversEveryInlineMediaPreferenceAndNothingElse() {
		let declared = Set(Preferences.InlineMedia.all.map(\.name))

		#expect(Set(sample.registrationDomain.keys) == declared)
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
