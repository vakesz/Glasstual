/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import SwiftUI
import Testing

/// Two isolated defaults suites and a scratch directory for one
/// preferences-transfer test, torn down by `cleanUp()`.
@MainActor
struct PreferencesTransferFixture {
	let stores: PreferencesTransferStores
	let directory: URL

	init() throws {
		let containerName = "PreferencesTransferTests.container.\(UUID().uuidString)"
		let standardName = "PreferencesTransferTests.standard.\(UUID().uuidString)"
		stores = try PreferencesTransferStores(
			container: #require(UserDefaults(suiteName: containerName)), containerDomain: containerName,
			standard: #require(UserDefaults(suiteName: standardName)), standardDomain: standardName
		)
		stores.container.register(defaults: Preferences.registrationDomain(for: .container).propertyListObject)
		stores.standard.register(defaults: Preferences.registrationDomain(for: .standard).propertyListObject)
		directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	func cleanUp() {
		stores.container.removePersistentDomain(forName: stores.containerDomain)
		stores.standard.removePersistentDomain(forName: stores.standardDomain)
		try? FileManager.default.removeItem(at: directory)
	}

	func session(backupDirectory: URL? = nil, world: IRCWorld? = nil) -> PreferencesTransferSession {
		PreferencesTransferSession(stores: stores,
		                           recoveryDirectory: backupDirectory ?? directory
		                           	.appendingPathComponent("Backups"),
		                           clientSource: world.map(PreferencesTransferClientSource.world) ?? .stored)
	}

	func reopenWorld() throws -> GLTClientEnvironmentFixture {
		let reopenedStores = try PreferencesTransferStores(
			container: #require(UserDefaults(suiteName: stores.containerDomain)),
			containerDomain: stores.containerDomain,
			standard: #require(UserDefaults(suiteName: stores.standardDomain)),
			standardDomain: stores.standardDomain
		)
		let fixture = GLTClientEnvironmentFixture(preferences: .current(stores: reopenedStores))
		let key = Preferences.Connection.clientList
		let saved = reopenedStores.store(for: key).object(forKey: key.name)
			.flatMap(PropertyListValue.init(propertyList:))
		for value in saved?.array ?? [] {
			let dictionary = try #require(value.dictionary)
			let configuration = try #require(PropertyListModel.decode(ClientConfig.self, from: dictionary))
			_ = fixture.world.createClient(with: configuration)
		}
		return fixture
	}

	func write(_ data: Data) throws -> URL {
		let url = directory.appendingPathComponent("Archive-\(UUID().uuidString).plist")
		try data.write(to: url)
		return url
	}
}
