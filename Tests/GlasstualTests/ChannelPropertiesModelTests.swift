/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Channel properties model")
struct ChannelPropertiesModelTests {
	/// `inlineMediaDisabled` and `inlineMediaEnabled` are the two halves of one
	/// override migrated from a single boolean, and
	/// `LogController.inlineMediaEnabledForView` reads exactly one of them
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
		#expect(model.inlineMediaOverrideTitle == ChannelPropertiesStrings.disableInlineMedia)
		#expect(model.inlineMediaOverride == false)
		model.inlineMediaOverride = true
		#expect(model.config.inlineMediaDisabled)
		#expect(model.config.inlineMediaEnabled == false)

		key.value = false
		#expect(model.overridesInlineMediaByDisabling == false)
		#expect(model.inlineMediaOverrideTitle == ChannelPropertiesStrings.showInlineMedia)
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
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANTYPES=#&!+")

		let exclamation = ChannelPropertiesModel(config: ChannelConfig(channelName: "!glasstual"), client: client)

		#expect(exclamation.channelNameValidationError == nil)
		#expect(exclamation.validateForSubmission())

		// `~` is in the connection-less union but not in this server's answer.
		let tilde = ChannelPropertiesModel(config: ChannelConfig(channelName: "~glasstual"), client: client)

		#expect(tilde.channelNameValidationError != nil)
		#expect(tilde.validateForSubmission() == false)
	}

	/// A sheet opened without a connection still has to validate something, so
	/// it keeps the syntactic check.
	@Test("Validation falls back to the syntactic check with no connection")
	func validationFallsBackWithoutAClient() {
		#expect(ChannelPropertiesModel(config: ChannelConfig(channelName: "#glasstual"))
			.channelNameValidationError == nil)
		#expect(ChannelPropertiesModel(config: ChannelConfig(channelName: "glasstual"))
			.channelNameValidationError != nil)
		#expect(ChannelPropertiesModel(config: ChannelConfig(channelName: ""))
			.channelNameValidationError != nil)
	}

	/** Every edit is re-validated, and against whatever answer is available at
	 the time: the sheet holds the connection weakly, so a client that goes away
	 mid-edit leaves the syntactic check behind rather than failing every name
	 from then on. */
	@Test("Editing a name re-validates it, and against the syntactic check once the client is gone")
	func editingRevalidates() throws {
		var client: GLTTestClient? = GLTTestClient()
		weak let weakClient = client
		client?.supportInfo.processConfigurationData("CHANTYPES=#")
		let model = ChannelPropertiesModel(config: ChannelConfig(), client: client)

		#expect(model.channelNameValidationError != nil)

		// `&` is a channel prefix, but not one this server named.
		model.channelName = "&glasstual"

		#expect(model.channelNameValidationError != nil)

		model.channelName = "#glasstual"

		#expect(model.channelNameValidationError == nil)

		client = nil

		try #require(weakClient == nil, "the sheet must not be what keeps the connection alive")

		/* With no connection left to ask, the check falls back to the union of
		 prefixes networks are known to use — which does include `&`. */
		model.channelName = "&elsewhere"

		#expect(model.channelNameValidationError == nil)

		model.channelName = "glasstual"

		#expect(model.channelNameValidationError != nil)
	}
}
