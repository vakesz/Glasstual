// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Networks of a bouncer account are discovered, so a portable archive carries
/// the account and never the networks.
@MainActor
@Suite("Bouncer networks in settings archives")
struct SettingsBouncerNetworkArchiveTests {
	private func account() -> ServerConfig {
		var config = ServerConfig(connectionName: "Account")
		config.bouncerHidesParent = true
		config.bouncerDiscoversNetworks = false
		return config
	}

	private func network(of parent: ServerConfig, removed: Bool = false) -> ServerConfig {
		var child = parent.derivingBouncerNetwork(BouncerNetwork(id: "1", name: "Libera"))
		child.bouncerNetwork?.isRemoved = removed
		return child
	}

	/// A portable document that names `sessions` as written, however they got there.
	private func portableDocument(_ sessions: [[String: PropertyListValue]]) throws -> Data {
		let root: [String: PropertyListValue] = [
			"format": .string(SettingsArchive.format),
			"version": .integer(SettingsArchive.version),
			"preferences": .dictionary([:]),
			"unset": .init([String]()),
			"clients": .array(sessions.map(PropertyListValue.dictionary)),
		]
		return try PropertyListSerialization.data(fromPropertyList: root.propertyListObject, format: .xml, options: 0)
	}

	@Test("The exportable list leaves the networks out and keeps everything else in order")
	func exportableDropsNetworks() {
		let parent = account()
		let plain = ServerConfig(connectionName: "Plain")

		let exportable = SettingsSessionArchive.exportable([parent, network(of: parent), plain])

		#expect(exportable.map(\.uniqueIdentifier) == [parent.uniqueIdentifier, plain.uniqueIdentifier])
	}

	@Test("A portable export carries the account and its switches but not its networks")
	func exportOmitsNetworks() throws {
		let parent = account()
		let archive = SettingsArchive(values: [:], unset: [], sessions: [parent, network(of: parent)])

		let decoded = try SettingsArchive.decode(archive.encoded())

		#expect(decoded.sessions?.map(\.uniqueIdentifier) == [parent.uniqueIdentifier])
		#expect(decoded.sessions?.first?.bouncerHidesParent == true)
		#expect(decoded.sessions?.first?.bouncerDiscoversNetworks == false)
	}

	@Test("A network inside a portable document is dropped on import")
	func importDropsNetworks() throws {
		let parent = account()
		let data = try portableDocument([
			SettingsSessionArchive.portableDictionary(parent),
			SettingsSessionArchive.portableDictionary(network(of: parent)),
		])

		let decoded = try SettingsArchive.decode(data)

		#expect(decoded.sessions?.map(\.uniqueIdentifier) == [parent.uniqueIdentifier])
	}

	@Test("A network with a malformed binding is a rejected document, not a shorter list")
	func malformedBindingIsRejected() throws {
		let parent = account()
		var dictionary = SettingsSessionArchive.portableDictionary(network(of: parent))
		dictionary["bouncerNetwork"] = .dictionary(["parentIdentifier": .string(""), "networkIdentifier": .string("1")])
		let data = try portableDocument([dictionary])

		#expect(throws: SettingsTransferError.self) { try SettingsArchive.decode(data) }
	}

	@Test("A binding with a field this build does not know is rejected")
	func unknownBindingFieldIsRejected() throws {
		let parent = account()
		var dictionary = SettingsSessionArchive.portableDictionary(network(of: parent))
		dictionary["bouncerNetwork"] = .dictionary([
			"parentIdentifier": .string("p"), "networkIdentifier": .string("1"), "extra": .string("x"),
		])
		let data = try portableDocument([dictionary])

		#expect(throws: SettingsTransferError.self) { try SettingsArchive.decode(data) }
	}

	@Test("A local recovery backup keeps the networks, their binding and their removed state")
	func recoveryKeepsNetworks() throws {
		let parent = account()
		let child = network(of: parent, removed: true)
		let archive = SettingsArchive(values: [:], unset: [], sessions: [parent, child], source: .localRecovery)

		let decoded = try SettingsArchive.decode(archive.recoveryEncoded(), source: .localRecovery)

		let restored = try #require(decoded.sessions?.last)
		#expect(decoded.sessions?.count == 2)
		#expect(restored.uniqueIdentifier == child.uniqueIdentifier)
		#expect(restored.bouncerNetwork == child.bouncerNetwork)
		#expect(restored.bouncerNetwork?.isRemoved == true)
	}

	@Test("A restore archive that omits the networks does not name them either")
	func exportedSnapshotHasNoNetworks() throws {
		let parent = account()
		let archive = SettingsArchive(values: [:], unset: [], sessions: [parent, network(of: parent)], source: .localRecovery)

		let portable = try SettingsArchive.decode(archive.encoded())

		#expect(portable.sessions?.count == 1)
	}
}
