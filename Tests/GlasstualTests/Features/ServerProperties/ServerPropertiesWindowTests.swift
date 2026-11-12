// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The Server Properties window is not modal, so what it does with edits is a
 decision of its own: when there are any, when it may close, what Revert and a
 change made somewhere else do to them, and what it is identified by. */
@MainActor
@Suite("Server properties window")
struct ServerPropertiesWindowTests {
	private static func savedConfiguration() -> ServerConfig {
		var config = ServerConfig(connectionName: "Libera")
		config.nickname = "someone"
		config.username = "someone"
		config.realName = "Someone"
		config.serverList = [ServerEndpoint(serverAddress: "irc.libera.chat", serverPort: 6697)]
		return config
	}

	@Test("An existing connection has nothing unsaved until a field or a secret changes")
	func unsavedChangesFollowEdits() {
		let model = ServerPropertiesModel(config: Self.savedConfiguration())
		#expect(model.hasUnsavedChanges == false)

		model.config.connectionName = "Libera.Chat"
		#expect(model.hasUnsavedChanges)
		model.config.connectionName = "Libera"
		#expect(model.hasUnsavedChanges == false)

		model.serverPort = "6667"
		#expect(model.hasUnsavedChanges)
		model.serverPort = "6697"

		model.setSecretText("secret", for: .nicknamePassword)
		#expect(model.hasUnsavedChanges)
	}

	@Test("Saving makes the saved edits the new baseline, secrets included")
	func savingClearsUnsavedChanges() throws {
		let model = ServerPropertiesModel(config: Self.savedConfiguration())
		model.config.connectionName = "Libera.Chat"
		model.setSecretText("secret", for: .nicknamePassword)
		let submitted = try #require(model.submittedConfig())

		model.markSaved(submitted)

		#expect(model.hasUnsavedChanges == false)
		#expect(try #require(model.submittedConfig()).pendingNicknamePassword == submitted.pendingNicknamePassword)
	}

	@Test("A new connection is unsaved once it leaves the network list")
	func newConnectionIsUnsavedOnTheForm() throws {
		let editor = ServerPropertiesEditor(session: nil) { _, _ in
			Issue.record("Choosing a network must not save it")
		}
		defer { editor.windowDidClose() }
		#expect(editor.model.hasUnsavedChanges == false)

		try #require(editor.model.templatePicker).selection = .customServer
		editor.model.applySelectedTemplate()

		#expect(editor.model.hasUnsavedChanges)
	}

	@Test("The window closes only with nothing unsaved and nothing being saved")
	func closingRule() {
		let model = ServerPropertiesModel(config: Self.savedConfiguration())
		#expect(ServerPropertiesWindows.closingIsAllowed(for: model))

		model.isSaving = true
		#expect(ServerPropertiesWindows.closingIsAllowed(for: model) == false)
		model.isSaving = false

		model.config.nickname = "someone-else"
		#expect(ServerPropertiesWindows.closingIsAllowed(for: model) == false)
	}

	@Test("A connection's window is identified by the connection, a new one by its new configuration")
	func windowIdentity() {
		let session = ServerSession(config: Self.savedConfiguration())
		let existing = ServerPropertiesEditor(session: session) { _, _ in }
		let new = ServerPropertiesEditor(session: nil) { _, _ in }
		defer {
			existing.windowDidClose()
			new.windowDidClose()
		}

		#expect(existing.windowID == session.uniqueIdentifier)
		#expect(new.windowID == new.model.config.uniqueIdentifier)
		#expect(new.windowID != existing.windowID)
		#expect(existing.windowTitle == "Libera")
		#expect(new.windowTitle == String(localized: .ServerProperties.newServerWindowTitle))
	}

	@Test("Revert puts an existing connection back to what is saved and keeps its window open")
	func revertRestoresSavedConfiguration() {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in }
		defer { editor.windowDidClose() }
		editor.model.config.nickname = "someone-else"
		editor.model.alternateNicknames = "other"

		editor.cancel()

		#expect(editor.model.hasUnsavedChanges == false)
		#expect(editor.model.config.nickname == "someone")
		#expect(editor.model.alternateNicknames.isEmpty)
		#expect(editor.closeRequested == false)
	}

	@Test("Cancelling a new connection closes its window")
	func cancellingNewConnectionCloses() {
		let editor = ServerPropertiesEditor(session: nil) { _, _ in }
		defer { editor.windowDidClose() }

		editor.cancel()

		#expect(editor.closeRequested)
	}

	@Test("A change made elsewhere is followed quietly when nothing is unsaved")
	func outsideChangeWithoutEditsReloads() {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in }
		defer { editor.windowDidClose() }

		session.config.realName = "Changed Elsewhere"
		ServerSessionConfigWasUpdated(subject: session).post()

		#expect(editor.asksToReload == false)
		#expect(editor.model.config.realName == "Changed Elsewhere")
	}

	@Test("A change made elsewhere over unsaved edits asks, and keeping the edits is the safe answer")
	func outsideChangeWithEditsAsks() {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in }
		defer { editor.windowDidClose() }
		editor.model.config.nickname = "someone-else"

		session.config.realName = "Changed Elsewhere"
		ServerSessionConfigWasUpdated(subject: session).post()
		#expect(editor.asksToReload)

		editor.answerReloadQuestion(reload: false)
		#expect(editor.asksToReload == false)
		#expect(editor.model.config.nickname == "someone-else")
		#expect(editor.model.config.realName == "Someone")

		ServerSessionConfigWasUpdated(subject: session).post()
		editor.answerReloadQuestion(reload: true)
		#expect(editor.model.config.realName == "Changed Elsewhere")
		#expect(editor.model.hasUnsavedChanges == false)
	}

	@Test("A restored window reopens on the pane it was left on, if the connection still lists it")
	func storedPane() {
		for pane in ServerPropertiesSelection.allCases {
			#expect(ServerPropertiesSelection(storedName: pane.storedName) == pane)
		}
		#expect(ServerPropertiesSelection(storedName: "nothing") == nil)

		var bouncerConfig = Self.savedConfiguration()
		bouncerConfig.bouncerNetwork = BouncerNetworkBinding(parentIdentifier: "parent", networkIdentifier: "1")
		let bouncerNetwork = ServerPropertiesModel(config: bouncerConfig)
		#expect(ServerPropertiesSelection.identity.isListed(for: bouncerNetwork) == false)
		#expect(ServerPropertiesSelection.channelList.isListed(for: bouncerNetwork))
		#expect(ServerPropertiesSelection.profile.isListed(for: bouncerNetwork) == false)
	}
}
