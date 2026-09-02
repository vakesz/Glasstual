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
}
