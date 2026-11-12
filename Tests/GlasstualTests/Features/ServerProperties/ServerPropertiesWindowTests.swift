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

	@Test("Closing asks over unsaved edits and waits for a save under way")
	func closePolicy() {
		let editor = ServerPropertiesEditor(session: ServerSession(config: Self.savedConfiguration())) { _, _ in }
		defer { editor.windowDidClose() }
		#expect(editor.closePolicy == .closes)

		editor.model.config.nickname = "someone-else"
		#expect(editor.closePolicy == .asks)

		editor.model.isSaving = true
		#expect(editor.closePolicy == .refuses)
	}

	@Test("The close review's buttons map to Save, Cancel and Don't Save")
	func closeReviewAnswers() {
		#expect(ServerPropertiesCloseAnswer(.default) == .save)
		#expect(ServerPropertiesCloseAnswer(.alternate) == .cancel)
		#expect(ServerPropertiesCloseAnswer(.other) == .dontSave)
		let request = ServerPropertiesEditor.closeReviewRequest(windowTitle: "Libera")
		#expect(request.title(for: .default) == PromptStrings.Action.save)
		#expect(request.title(for: .alternate) == PromptStrings.Action.cancel)
		#expect(request.allowsInline == false)
	}

	@Test("Cancel keeps the edits and the window")
	func closeReviewCancel() async {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in
			Issue.record("Cancel must not save")
		}
		defer { editor.windowDidClose() }
		editor.model.config.nickname = "someone-else"

		#expect(await editor.answerCloseReview(.cancel) == false)
		#expect(editor.model.config.nickname == "someone-else")
		#expect(editor.model.hasUnsavedChanges)
	}

	@Test("Don't Save throws the edits away and lets the window close")
	func closeReviewDontSave() async {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in
			Issue.record("Don't Save must not save")
		}
		defer { editor.windowDidClose() }
		editor.model.config.nickname = "someone-else"

		#expect(await editor.answerCloseReview(.dontSave))
		#expect(editor.model.config.nickname == "someone")
		#expect(editor.model.hasUnsavedChanges == false)
		#expect(session.config.nickname == "someone")
	}

	@Test("Save stores the edits and lets the window close", .timeLimit(.minutes(1)))
	func closeReviewSave() async {
		let session = ServerSession(config: Self.savedConfiguration())
		var saved: [ServerConfig] = []
		let editor = ServerPropertiesEditor(session: session) { config, _ in saved.append(config) }
		defer { editor.windowDidClose() }
		editor.credentialPersistence = KeychainPersistence { _ in }
		editor.settingsSaves = SettingsSaveQueue()
		editor.model.config.nickname = "someone-else"

		#expect(await editor.answerCloseReview(.save))
		#expect(saved.map(\.nickname) == ["someone-else"])
		#expect(editor.model.hasUnsavedChanges == false)
		#expect(editor.closeRequested == false)
	}

	@Test("A save that fails keeps the edits and the window open", .timeLimit(.minutes(1)))
	func closeReviewFailedSave() async {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in
			Issue.record("A failed keychain write must not save the configuration")
		}
		defer { editor.windowDidClose() }
		editor.credentialPersistence = KeychainPersistence { _ in throw CocoaError(.fileWriteUnknown) }
		editor.settingsSaves = SettingsSaveQueue()
		editor.model.config.nickname = "someone-else"
		editor.model.setSecretText("secret", for: .nicknamePassword)

		#expect(await editor.answerCloseReview(.save) == false)
		#expect(editor.model.hasUnsavedChanges)
		#expect(editor.model.isSaving == false)
		#expect(editor.closePolicy == .asks)
	}

	@Test("A save the form refuses keeps the edits and the window open")
	func closeReviewInvalidSave() async {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in
			Issue.record("An invalid form must not be saved")
		}
		defer { editor.windowDidClose() }
		editor.credentialPersistence = KeychainPersistence { _ in }
		editor.settingsSaves = SettingsSaveQueue()
		editor.model.serverPort = "70000"

		#expect(await editor.answerCloseReview(.save) == false)
		#expect(editor.model.hasUnsavedChanges)
	}

	@Test("A new connection's window goes with Don't Save")
	func closeReviewDontSaveNewConnection() async throws {
		let editor = ServerPropertiesEditor(session: nil) { _, _ in }
		defer { editor.windowDidClose() }
		try #require(editor.model.templatePicker).selection = .customServer
		editor.model.applySelectedTemplate()

		#expect(await editor.answerCloseReview(.dontSave))
		#expect(editor.closeRequested)
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

	@Test("An address book edit made in the People window is not a configuration change here")
	func addressBookChangeDoesNotAsk() {
		let session = ServerSession(config: Self.savedConfiguration())
		let editor = ServerPropertiesEditor(session: session) { _, _ in }
		defer { editor.windowDidClose() }
		editor.model.config.nickname = "someone-else"

		session.config.ignoreList.append(.newIgnoreEntry(forHostmask: "troll!*@*"))
		ServerSessionConfigWasUpdated(subject: session).post()

		#expect(editor.asksToReload == false)
		#expect(editor.model.config.nickname == "someone-else")
		#expect(editor.model.hasUnsavedChanges)
	}

	@Test("Only what the window edits counts as a change to its configuration")
	func editedConfigurationChange() {
		let saved = Self.savedConfiguration()
		var addressBook = saved
		addressBook.ignoreList = [.newIgnoreEntry(forHostmask: "troll!*@*")]
		#expect(ServerPropertiesEditor.changesEditedConfiguration(from: saved, to: addressBook) == false)

		var both = addressBook
		both.realName = "Changed Elsewhere"
		#expect(ServerPropertiesEditor.changesEditedConfiguration(from: saved, to: both))
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
