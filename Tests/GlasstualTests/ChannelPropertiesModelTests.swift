/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel properties model")
struct ChannelPropertiesModelTests {
	/// `inlineMediaDisabled` and `inlineMediaEnabled` are the two halves of one
	/// override migrated from a single boolean, and
	/// `TranscriptController.inlineMediaEnabledForView` reads exactly one of them
	/// depending on the application-wide preference. The sheet used to edit both
	/// as independent switches, so one of them was always inert and the pair
	/// could be left contradicting each other.
	@Test("The inline-media override edits the flag the global preference reads")
	func inlineMediaOverrideFollowsTheGlobalPreference() {
		let key = Preferences.Messages.showInlineMedia
		let original = key.value
		defer { key.value = original }

		var config = ChannelConfig(channelName: "#example")
		config.inlineMediaDisabled = false
		config.inlineMediaEnabled = false
		let model = ChannelPropertiesModel(config: config)

		key.value = true
		#expect(model.overridesInlineMediaByDisabling)
		#expect(model.inlineMediaOverrideTitle == LocalizedStringResource.ChannelProperties.disableInlineMedia)
		#expect(model.inlineMediaOverride == false)
		model.inlineMediaOverride = true
		#expect(model.config.inlineMediaDisabled)
		#expect(model.config.inlineMediaEnabled == false)

		key.value = false
		#expect(model.overridesInlineMediaByDisabling == false)
		#expect(model.inlineMediaOverrideTitle == LocalizedStringResource.ChannelProperties.showInlineMedia)
		#expect(model.inlineMediaOverride == false)
		model.inlineMediaOverride = true
		#expect(model.config.inlineMediaEnabled)
	}

	/** The connection-less check is a union of the prefixes networks are known
	 to use, which is both too wide and too narrow. A server whose `CHANTYPES`
	 is narrower accepts a name here that it will refuse on the wire, and a
	 server whose `CHANTYPES` names a prefix the union does not include has
	 channels the sheet would never let the user save. */
	@Test("Validation follows the server's CHANTYPES when there is a connection")
	func validationFollowsTheServersChannelTypes() {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANTYPES=#&!+")

		let exclamation = ChannelPropertiesModel(config: ChannelConfig(channelName: "!glasstual"), client: client)

		#expect(exclamation.channelNameIsValid)
		#expect(exclamation.validateForSubmission())

		// `~` is in the connection-less union but not in this server's answer.
		let tilde = ChannelPropertiesModel(config: ChannelConfig(channelName: "~glasstual"), client: client)

		#expect(tilde.channelNameIsValid == false)
		#expect(tilde.validateForSubmission() == false)
	}

	/** A sheet for a channel that does not exist yet opens on an empty field.
	 The name is already known to be unusable, but saying so beside the field —
	 in red, with a border around it — before anything has been typed tells the
	 person they got something wrong before they did anything. */
	@Test("An untouched field carries no message, and a refused save does")
	func theMessageWaitsForASaveToBeRefused() {
		let model = ChannelPropertiesModel(config: ChannelConfig())

		#expect(model.channelNameIsValid == false)
		#expect(model.channelNameValidationMessage == nil)

		#expect(model.validateForSubmission() == false)
		#expect(model.channelNameValidationMessage == String(localized: .ChannelProperties.pleaseEnterAProperlyFormattedChannel))

		// And it goes as soon as the name is one, without another save.
		model.channelName = "#glasstual"

		#expect(model.channelNameValidationMessage == nil)
	}

	/// A sheet opened without a connection still has to validate something, so
	/// it keeps the syntactic check.
	@Test("Validation falls back to the syntactic check with no connection")
	func validationFallsBackWithoutAClient() {
		#expect(ChannelPropertiesModel(config: ChannelConfig(channelName: "#glasstual"))
			.channelNameIsValid)
		#expect(ChannelPropertiesModel(config: ChannelConfig(channelName: "glasstual"))
			.channelNameIsValid == false)
		#expect(ChannelPropertiesModel(config: ChannelConfig(channelName: ""))
			.channelNameIsValid == false)
	}

	/** Every edit is re-validated, and against whatever answer is available at
	 the time: the sheet holds the connection weakly, so a client that goes away
	 mid-edit leaves the syntactic check behind rather than failing every name
	 from then on. */
	@Test("Editing a name re-validates it, and against the syntactic check once the client is gone")
	func editingRevalidates() throws {
		var client: TestClient? = TestClient()
		weak let weakClient = client
		client?.supportInfo.processConfigurationData("CHANTYPES=#")
		let model = ChannelPropertiesModel(config: ChannelConfig(), client: client)

		#expect(model.channelNameIsValid == false)

		// `&` is a channel prefix, but not one this server named.
		model.channelName = "&glasstual"

		#expect(model.channelNameIsValid == false)

		model.channelName = "#glasstual"

		#expect(model.channelNameIsValid)

		client = nil

		try #require(weakClient == nil, "the sheet must not be what keeps the connection alive")

		/* With no connection left to ask, the check falls back to the union of
		 prefixes networks are known to use — which does include `&`. */
		model.channelName = "&elsewhere"

		#expect(model.channelNameIsValid)

		model.channelName = "glasstual"

		#expect(model.channelNameIsValid == false)
	}

	@Test("The key length caption counts UTF-8 bytes of the token that will be sent")
	func keyLengthCountsSubmittedBytes() {
		let client = TestClient()
		client.supportInfo.processConfigurationData("KEYLEN=3")
		let model = ChannelPropertiesModel(config: ChannelConfig(channelName: "#swift"), client: client)
		model.secretKey = "  é ignored"
		#expect(model.secretKeyLengthCaption == String(localized: .ChannelProperties.secretKeyLength(2, 3)))
		#expect(model.secretKeyIsTooLong == false)

		model.secretKey = "💬"
		#expect(model.secretKeyIsTooLong)
	}

	/** Emptying the key field used to submit `nil`, which the configuration
	 read as "no edit": the stored key stayed in the keychain, was sent on every
	 later JOIN, and came back the next time the sheet opened. */
	@Test("Emptying a loaded channel key asks for the stored key to go", .timeLimit(.minutes(1)))
	func emptiedChannelKeyIsCleared() async {
		let config = ChannelConfig(channelName: "#glasstual")
		#expect(config.keychainItem.write("stored-key"))
		defer { config.keychainItem.delete() }

		let model = ChannelPropertiesModel(config: config)
		await model.loadSecretKey()

		#expect(model.secretKey == "stored-key")
		#expect(model.submittedConfig.pendingSecretKey == .unchanged)

		model.secretKey = ""

		#expect(model.submittedConfig.pendingSecretKey == .cleared)

		model.secretKey = "  replacement trailing"

		#expect(model.submittedConfig.pendingSecretKey == .set("replacement"))
	}

	/// The key is read after the sheet is on screen, so saving before the read
	/// answers must not submit the still-empty field as an emptied one.
	@Test("Saving before the keychain answers leaves the channel key alone")
	func savingBeforeTheKeyLoadsKeepsIt() {
		let model = ChannelPropertiesModel(config: ChannelConfig(channelName: "#glasstual"))

		#expect(model.secretKey.isEmpty)
		#expect(model.submittedConfig.pendingSecretKey == .unchanged)
	}

	/// A field the person has typed into keeps what they typed when the read
	/// lands afterwards, and a configuration already carrying an edit is not
	/// overwritten by what the keychain holds.
	@Test("The keychain read never overwrites an edit", .timeLimit(.minutes(1)))
	func keychainReadKeepsEdits() async {
		var config = ChannelConfig(channelName: "#glasstual")
		#expect(config.keychainItem.write("stored-key"))
		defer { config.keychainItem.delete() }

		let typed = ChannelPropertiesModel(config: config)
		typed.secretKey = "typed"
		await typed.loadSecretKey()

		#expect(typed.secretKey == "typed")

		config.pendingSecretKey = .cleared
		let cleared = ChannelPropertiesModel(config: config)
		await cleared.loadSecretKey()

		#expect(cleared.secretKey.isEmpty)
		#expect(cleared.submittedConfig.pendingSecretKey == .cleared)
	}
}
