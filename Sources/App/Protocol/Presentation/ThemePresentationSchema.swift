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

import Foundation

nonisolated struct StringSchemaValues<SchemaKey: Hashable & RawRepresentable>: ExpressibleByDictionaryLiteral
	where SchemaKey.RawValue == String
{
	private(set) var rawValues: [String: Any]
	var anyHashableValues: [AnyHashable: Any] {
		Dictionary(uniqueKeysWithValues: rawValues.map { (AnyHashable($0.key), $0.value) })
	}

	init() {
		rawValues = [:]
	}

	init(rawValues: [String: Any]) {
		self.rawValues = rawValues
	}

	init(dictionaryLiteral elements: (SchemaKey, Any)...) {
		rawValues = Dictionary(uniqueKeysWithValues: elements.map { ($0.rawValue, $1) })
	}

	subscript(key: SchemaKey) -> Any? {
		get { rawValues[key.rawValue] }
		set { rawValues[key.rawValue] = newValue }
	}

	func value<Value>(for key: SchemaKey, as _: Value.Type = Value.self) -> Value? {
		rawValues[key.rawValue] as? Value
	}

	mutating func merge(_ other: Self) {
		rawValues.merge(other.rawValues) { _, replacement in replacement }
	}
}

enum LogRendererConfigurationKey: String, CaseIterable, Sendable {
	case renderLinks = "TVCLogRendererConfigurationRenderLinksAttribute"
	case lineType = "TVCLogRendererConfigurationLineTypeAttribute"
	case memberType = "TVCLogRendererConfigurationMemberTypeAttribute"
	case highlightKeywords = "TVCLogRendererConfigurationHighlightKeywordsAttribute"
	case excludedKeywords = "TVCLogRendererConfigurationExcludedKeywordsAttribute"
	case doNotEscapeBody = "TVCLogRendererConfigurationDoNotEscapeBodyAttribute"
	case preferredFont = "TVCLogRendererConfigurationAttributedStringPreferredFontAttribute"
	case preferredFontColor = "TVCLogRendererConfigurationAttributedStringPreferredFontColorAttribute"
	case inlineMediaEnabled = "TVCLogRendererConfigurationInlineMediaEnabledAttribute"
}

enum LogRendererResultKey: String, CaseIterable, Sendable {
	case links = "TVCLogRendererResultsListOfLinksInBodyAttribute"
	case mappedLinks = "TVCLogRendererResultsListOfLinksMappedInBodyAttribute"
	case keywordMatchFound = "TVCLogRendererResultsKeywordMatchFoundAttribute"
	case users = "TVCLogRendererResultsListOfUsersFoundAttribute"
	case bodyWithoutEffects = "TVCLogRendererResultsOriginalBodyWithoutEffectsAttribute"
}

enum LogPresentationResultKey: String, CaseIterable, Sendable {
	case processInlineMedia
	case pluginObject = "pluginConcreteObject"
}

enum RenderedLogEntryKey: String, CaseIterable, Sendable {
	case html
	case lineNumber
	case timestamp
}

enum LogViewStateKey: String, CaseIterable, Sendable {
	case reloadingTheme
	case scrollbackLimit
	case selected
	case textSizeMultiplier
	case visible
}

enum ThemeTemplateName: String, CaseIterable, Sendable {
	case baseLayout
	case formattedMessageFragment
	case historyIndicator
	case renderedChannelNameLinkResource
	case renderedStandardAnchorLinkResource
}

enum ThemeTemplateAttribute: String, CaseIterable, Sendable {
	case activeStyleAbsolutePath
	case activeStyleCSSFiles
	case activeStyleJSFiles
	case anchorInlineMediaAvailable
	case anchorInlineMediaUniqueID
	case anchorLocation
	case anchorTitle
	case appearanceDescription
	case appearanceToken
	case applicationResourcePath
	case applicationTemplatesPath
	case cacheToken
	case channelName
	case command
	case configuredServerName
	case dateIndicatorMessage
	case deliveryState
	case formattedMessage
	case formattedNickname
	case formattedTimestamp
	case fragmentBackgroundColor
	case fragmentBackgroundColorIsSet
	case fragmentForegroundColor
	case fragmentForegroundColorIsSet
	case fragmentIsBold
	case fragmentIsBoldClosedAtEnd
	case fragmentIsBoldClosedAtStart
	case fragmentIsBoldOpened
	case fragmentIsItalicized
	case fragmentIsItalicizedClosedAtEnd
	case fragmentIsItalicizedClosedAtStart
	case fragmentIsItalicizedOpened
	case fragmentIsMonospace
	case fragmentIsMonospaceClosedAtEnd
	case fragmentIsMonospaceClosedAtStart
	case fragmentIsMonospaceOpened
	case fragmentIsSpoiler
	case fragmentIsStruckthrough
	case fragmentIsStruckthroughClosedAtEnd
	case fragmentIsStruckthroughClosedAtStart
	case fragmentIsStruckthroughOpened
	case fragmentIsUnderlined
	case fragmentIsUnderlinedClosedAtEnd
	case fragmentIsUnderlinedClosedAtStart
	case fragmentIsUnderlinedOpened
	case fragmentTextColor
	case fragmentTextColorClosedAtEnd
	case fragmentTextColorClosedAtStart
	case fragmentTextColorIsSet
	case fragmentTextColorOpened
	case fragmentTextColorUsesStyleTag
	case highlightAttribute
	case historyIndicatorMessage
	case inlineMediaEnabled
	case inlineNicknameColorStyle
	case inlineNicknameMatchFound
	case inlineNicknameUserModeSymbol
	case isChannelView
	case isEncrypted
	case isHighlight
	case isNicknameAvailable
	case isPrivateMessageView
	case isReloadingStyle
	case isRemoteMessage
	case isUtilityView
	case lineClassAttribute
	case lineNumber
	case lineRenderTime
	case lineType
	case localizedTimestamp
	case message
	case messageFragment
	case messageFragmentEscaped
	case messageIdentifier
	case nickname
	case nicknameColorHashingEnabled
	case nicknameColorStyle
	case nicknameColorStyleOverride
	case nicknameIndentationAvailable
	case nicknameType
	case operatingSystemVersion
	case predefinedTimestampWidth
	case rawCommand
	case reactionsJSON
	case replyToMessageIdentifier
	case sessionIndicatorMessage
	case showDateIndicator
	case showSessionIndicator
	case sidebarInversionIsEnabled
	case textDirectionToken
	case timestamp
	case userConfiguredFontName
	case userConfiguredFontSize
	case userConfiguredTextEncoding
	case userStyleSheetRules
	case usesCustomScrollers
	case viewTypeToken
}

enum ThemeSettingKey: String, CaseIterable, Sendable {
	case appearance = "Appearance"
	case channelViewOverlayColor = "Channel View Overlay Color"
	case forceInvertSidebars = "Force Invert Sidebars"
	case indentationOffset = "Indentation Offset"
	case keyValueStoreName = "Key-value Store Name"
	case nicknameColorStyle = "Nickname Color Style"
	case nicknameFormat = "Nickname Format"
	case overrideChannelFont = "Override Channel Font"
	case postAppearanceChanges = "Post Glasstual.appearanceDidChange() Notifications"
	case postHandleEvent = "Post Glasstual.handleEvent() Notifications"
	case postPreferenceChanges = "Post Glasstual.preferencesDidChange() Notifications"
	case templateEngineVersions = "Template Engine Versions"
	case timestampFormat = "Timestamp Format"
	case underlyingWindowColor = "Underlying Window Color"
}

enum ThemeFontSettingKey: String, CaseIterable, Sendable {
	case name = "Font Name"
	case size = "Font Size"
}

/// The two appearances a style declares and a channel view renders under. One
/// vocabulary: the theme's declared appearance and the view's current one are
/// compared against each other.
enum ThemeAppearanceToken: String, CaseIterable, Sendable {
	case dark
	case light
}

enum ThemeNicknameColorToken: String, CaseIterable, Sendable {
	case dark = "HSL-dark"
	case light = "HSL-light"
}

enum ThemeTemplateVersionKey: String, CaseIterable, Sendable {
	case fallback = "default"
}

enum ThemePreferenceNamespace: String, Sendable {
	case settingsStore = "Internal Theme Settings Key-value Store -> "
}

enum ThemeResourcePath: String, CaseIterable, Sendable {
	case cachedStyleResources = "Cached-Style-Resources"
	case defaultTemplates = "Style Default Templates"
	case designStyleSheet = "design.css"
	case legacySettings = "Data/Settings/styleSettings.plist"
	case legacyTemplates = "Data/Templates"
	case lineTypes = "Line Types"
	case scripts = "scripts.js"
	case settings = "settings.plist"
	case templateLineTypes = "TemplateLineTypes"
	case templates = "Templates"
	case varieties = "Varieties"
}

enum ThemeResourceExtension: String, CaseIterable, Sendable {
	case styleSheet = "css"
	case javaScript = "js"
}

enum ChannelViewTypeToken: String, Sendable {
	case server
}

enum ChannelViewTextDirectionToken: String, Sendable {
	case leftToRight = "ltr"
	case rightToLeft = "rtl"
}

enum LogLineClassToken: String, Sendable {
	case event
	case text
}

typealias LogRendererConfiguration = StringSchemaValues<LogRendererConfigurationKey>
typealias LogRendererResults = StringSchemaValues<LogRendererResultKey>
typealias RenderedLogEntry = StringSchemaValues<RenderedLogEntryKey>
typealias LogViewState = StringSchemaValues<LogViewStateKey>
typealias ThemeTemplateAttributes = StringSchemaValues<ThemeTemplateAttribute>
typealias ThemeSettingValues = StringSchemaValues<ThemeSettingKey>
typealias ThemeFontSettingValues = StringSchemaValues<ThemeFontSettingKey>
typealias ThemeTemplateVersionValues = StringSchemaValues<ThemeTemplateVersionKey>
