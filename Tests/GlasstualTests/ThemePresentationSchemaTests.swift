/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

@testable import Glasstual
import Testing

/// A theme, a plugin or the JavaScript running inside a style reads these keys
/// by name, so the typed enums have to keep spelling them exactly as the
/// retired string constants did.
@MainActor
@Suite("Theme presentation schema")
struct ThemePresentationSchemaTests {
	@Test("The renderer configuration keys keep the names themes and plugins pass in")
	func rendererConfigurationSchemaRetainsExternalKeys() {
		let expected = [
			"TVCLogRendererConfigurationRenderLinksAttribute",
			"TVCLogRendererConfigurationLineTypeAttribute",
			"TVCLogRendererConfigurationMemberTypeAttribute",
			"TVCLogRendererConfigurationHighlightKeywordsAttribute",
			"TVCLogRendererConfigurationExcludedKeywordsAttribute",
			"TVCLogRendererConfigurationDoNotEscapeBodyAttribute",
			"TVCLogRendererConfigurationAttributedStringPreferredFontAttribute",
			"TVCLogRendererConfigurationAttributedStringPreferredFontColorAttribute",
			"TVCLogRendererConfigurationInlineMediaEnabledAttribute",
		]

		#expect(LogRendererConfigurationKey.allCases.map(\.rawValue) == expected)
		#expect(String.renderLinksAttribute == expected[0])
		#expect(String.attributedStringPreferredFontColorAttribute == expected[7])
	}

	@Test("The renderer result keys keep the names their readers look up")
	func rendererResultSchemaRetainsExternalKeys() {
		let expected = [
			"TVCLogRendererResultsListOfLinksInBodyAttribute",
			"TVCLogRendererResultsListOfLinksMappedInBodyAttribute",
			"TVCLogRendererResultsKeywordMatchFoundAttribute",
			"TVCLogRendererResultsListOfUsersFoundAttribute",
			"TVCLogRendererResultsOriginalBodyWithoutEffectsAttribute",
		]

		#expect(LogRendererResultKey.allCases.map(\.rawValue) == expected)
		#expect(String.listOfLinksInBodyAttribute == expected[0])
		#expect(String.originalBodyWithoutEffectsAttribute == expected[4])
	}

	@Test("Each template name is the file name a theme ships")
	func templateNamesRetainThemeFileNames() {
		#expect(
			ThemeTemplateName.allCases.map(\.rawValue) == [
				"baseLayout",
				"formattedMessageFragment",
				"historyIndicator",
				"renderedChannelNameLinkResource",
				"renderedStandardAnchorLinkResource",
			]
		)
	}

	@Test("Each template attribute is a mustache variable a theme can name")
	func templateAttributeSchemaRetainsMustacheNames() {
		let expected = Set([
			"activeStyleAbsolutePath",
			"activeStyleCSSFiles",
			"activeStyleJSFiles",
			"anchorInlineMediaAvailable",
			"anchorInlineMediaUniqueID",
			"anchorLocation",
			"anchorTitle",
			"appearanceDescription",
			"appearanceToken",
			"applicationResourcePath",
			"applicationTemplatesPath",
			"cacheToken",
			"channelName",
			"command",
			"configuredServerName",
			"dateIndicatorMessage",
			"deliveryState",
			"formattedMessage",
			"formattedNickname",
			"formattedTimestamp",
			"fragmentBackgroundColor",
			"fragmentBackgroundColorIsSet",
			"fragmentForegroundColor",
			"fragmentForegroundColorIsSet",
			"fragmentIsBold",
			"fragmentIsBoldClosedAtEnd",
			"fragmentIsBoldClosedAtStart",
			"fragmentIsBoldOpened",
			"fragmentIsItalicized",
			"fragmentIsItalicizedClosedAtEnd",
			"fragmentIsItalicizedClosedAtStart",
			"fragmentIsItalicizedOpened",
			"fragmentIsMonospace",
			"fragmentIsMonospaceClosedAtEnd",
			"fragmentIsMonospaceClosedAtStart",
			"fragmentIsMonospaceOpened",
			"fragmentIsSpoiler",
			"fragmentIsStruckthrough",
			"fragmentIsStruckthroughClosedAtEnd",
			"fragmentIsStruckthroughClosedAtStart",
			"fragmentIsStruckthroughOpened",
			"fragmentIsUnderlined",
			"fragmentIsUnderlinedClosedAtEnd",
			"fragmentIsUnderlinedClosedAtStart",
			"fragmentIsUnderlinedOpened",
			"fragmentTextColor",
			"fragmentTextColorClosedAtEnd",
			"fragmentTextColorClosedAtStart",
			"fragmentTextColorIsSet",
			"fragmentTextColorOpened",
			"fragmentTextColorUsesStyleTag",
			"highlightAttribute",
			"historyIndicatorMessage",
			"inlineMediaEnabled",
			"inlineNicknameColorStyle",
			"inlineNicknameMatchFound",
			"inlineNicknameUserModeSymbol",
			"isChannelView",
			"isEncrypted",
			"isHighlight",
			"isNicknameAvailable",
			"isPrivateMessageView",
			"isReloadingStyle",
			"isRemoteMessage",
			"isUtilityView",
			"lineClassAttribute",
			"lineNumber",
			"lineRenderTime",
			"lineType",
			"localizedTimestamp",
			"message",
			"messageFragment",
			"messageFragmentEscaped",
			"messageIdentifier",
			"nickname",
			"nicknameColorHashingEnabled",
			"nicknameColorStyle",
			"nicknameColorStyleOverride",
			"nicknameIndentationAvailable",
			"nicknameType",
			"operatingSystemVersion",
			"predefinedTimestampWidth",
			"rawCommand",
			"reactionsJSON",
			"replyToMessageIdentifier",
			"sessionIndicatorMessage",
			"showDateIndicator",
			"showSessionIndicator",
			"sidebarInversionIsEnabled",
			"textDirectionToken",
			"timestamp",
			"userConfiguredFontName",
			"userConfiguredFontSize",
			"userConfiguredTextEncoding",
			"userStyleSheetRules",
			"usesCustomScrollers",
			"viewTypeToken",
		])

		#expect(Set(ThemeTemplateAttribute.allCases.map(\.rawValue)) == expected)
	}

	@Test("Each theme setting is the key a style's property list writes")
	func themeSettingsSchemaRetainsPropertyListKeys() {
		let expected = Set([
			"Appearance",
			"Channel View Overlay Color",
			"Force Invert Sidebars",
			"Indentation Offset",
			"Key-value Store Name",
			"Nickname Color Style",
			"Nickname Format",
			"Override Channel Font",
			"Post Glasstual.appearanceDidChange() Notifications",
			"Post Glasstual.handleEvent() Notifications",
			"Post Glasstual.preferencesDidChange() Notifications",
			"Template Engine Versions",
			"Timestamp Format",
			"Underlying Window Color",
		])

		#expect(Set(ThemeSettingKey.allCases.map(\.rawValue)) == expected)
		#expect(ThemeFontSettingKey.name.rawValue == "Font Name")
		#expect(ThemeFontSettingKey.size.rawValue == "Font Size")
		#expect(ThemeNicknameColorToken.light.rawValue == "HSL-light")
		#expect(ThemeNicknameColorToken.dark.rawValue == "HSL-dark")
	}

	@Test("The typed builder exports the exact strings and passes a third-party key through")
	func typedBuilderExportsExactStringsAndPreservesDynamicInput() {
		var attributes: ThemeTemplateAttributes = [
			.channelName: "#swift",
			.isChannelView: true,
		]
		attributes[.viewTypeToken] = "channel"

		#expect(attributes.rawValues["channelName"] as? String == "#swift")
		#expect(attributes.rawValues["isChannelView"] as? Bool == true)
		#expect(attributes.rawValues["viewTypeToken"] as? String == "channel")

		let configuration = LogRendererConfiguration(rawValues: ["thirdPartyRendererKey": 7])

		#expect(configuration.rawValues["thirdPartyRendererKey"] as? Int == 7)
	}
}
