@testable import Glasstual
import Testing

/// The script bridge is the only path from page JavaScript into the app, so
/// its surface is enumerated rather than discovered through the ObjC runtime.
@Suite("Log view script bridge")
@MainActor
struct LogScriptBridgeTests {
	@Test("Every registered message name has a handler bound")
	func everyMessageHasAHandler() {
		#expect(TVCLogScriptEventSink.messagesWithoutHandlers.isEmpty)
	}

	@Test("Registered names are unique and cover every case")
	func registeredNamesMatchTheEnum() {
		let names = TVCLogScriptEventSink.registeredMessageNames
		#expect(names.count == TVCLogScriptEventSink.ScriptMessage.allCases.count)
		#expect(Set(names).count == names.count)
	}

	/// OTR is gone. The name used to be registered with nothing implementing
	/// it, and the runtime dispatch swallowed it without a word.
	@Test("The OTR authenticate-user bridge is not registered")
	func encryptionAuthenticateUserIsGone() {
		#expect(TVCLogScriptEventSink.ScriptMessage(rawValue: "encryptionAuthenticateUser") == nil)
		#expect(TVCLogScriptEventSink.registeredMessageNames.contains("encryptionAuthenticateUser") == false)
	}

	@Test(
		"Presentation preferences a style asks for are readable",
		arguments: [
			"themeName",
			"themeNicknameFormat",
			"themeTimestampFormat",
			"themeChannelViewFontName",
			"themeChannelViewFontSize",
			"showInlineMedia",
			"rightToLeftFormatting",
		]
	)
	func permittedPreferencesResolve(name: String) {
		let read = TVCLogScriptEventSink.permittedPreferences[name]
		#expect(read != nil)
		#expect(read?() != nil)
	}

	/// `retrievePreferencesWithMethodName` used to resolve any zero-argument
	/// class method, which included everything inherited from `NSObject` and
	/// every setter and lifecycle hook on `TextualPreferences` itself.
	@Test(
		"Runtime and mutating methods are not reachable",
		arguments: [
			"alloc",
			"new",
			"class",
			"self",
			"description",
			"initPreferences",
			"registerDefaults",
			"populateDefaultNickname",
			"clientList",
			"cleanUpHighlightKeywords",
		]
	)
	func unlistedMethodsAreRefused(name: String) {
		#expect(TVCLogScriptEventSink.permittedPreferences[name] == nil)
	}

	@Test("Nothing readable is a setter")
	func nothingReadableIsASetter() {
		let setters = TVCLogScriptEventSink.permittedPreferences.keys.filter { $0.hasPrefix("set") }
		#expect(setters.isEmpty)
	}
}
