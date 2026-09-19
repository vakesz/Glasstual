// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

/// Two isolated defaults suites and a scratch directory for one
/// settings-transfer test, torn down by `cleanUp()`.
@MainActor
struct SettingsTransferFixture {
	let stores: SettingsStores
	let directory: URL

	init() throws {
		let containerName = "PreferencesTransferTests.container.\(UUID().uuidString)"
		let standardName = "PreferencesTransferTests.standard.\(UUID().uuidString)"
		stores = try SettingsStores(
			container: #require(UserDefaults(suiteName: containerName)), containerDomain: containerName,
			standard: #require(UserDefaults(suiteName: standardName)), standardDomain: standardName
		)
		stores.container.register(defaults: SettingsKeys.registrationDomain(for: .container).propertyListObject)
		stores.standard.register(defaults: SettingsKeys.registrationDomain(for: .standard).propertyListObject)
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

	func session(backupDirectory: URL? = nil, chatSession: ChatSession? = nil) -> SettingsTransferSession {
		SettingsTransferSession(stores: stores,
		                        recoveryDirectory: backupDirectory ?? directory
		                        	.appendingPathComponent("Backups"),
		                        sessionSource: chatSession.map(SettingsTransferSessionSource.chatSession) ?? .stored)
	}

	func reopenChatSession() throws -> ChatEnvironmentFixture {
		let reopenedStores = try SettingsStores(
			container: #require(UserDefaults(suiteName: stores.containerDomain)),
			containerDomain: stores.containerDomain,
			standard: #require(UserDefaults(suiteName: stores.standardDomain)),
			standardDomain: stores.standardDomain
		)
		let fixture = ChatEnvironmentFixture(settings: .current(stores: reopenedStores))
		let key = SettingsKeys.Sessions.serverSessions
		let saved = reopenedStores.store(for: key).object(forKey: key.name)
			.flatMap(PropertyListValue.init(propertyList:))
		for value in saved?.array ?? [] {
			let dictionary = try #require(value.dictionary)
			let configuration = try #require(PropertyListModel.decode(ServerConfig.self, from: dictionary))
			_ = fixture.chatSession.createSession(with: configuration)
		}
		return fixture
	}

	func write(_ data: Data) throws -> URL {
		let url = directory.appendingPathComponent("Archive-\(UUID().uuidString).plist")
		try data.write(to: url)
		return url
	}
}
