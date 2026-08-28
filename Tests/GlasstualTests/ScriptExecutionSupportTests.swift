/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@Suite("Script execution support")
struct ScriptExecutionSupportTests {
	private static let subroutineNameKeyword = AEKeyword(0x736E_616D)

	@Test("The Apple event carries the requested handler name")
	func appleEventCarriesHandlerName() throws {
		for handler in [ScriptExecutionSupport.handlerName, ScriptExecutionSupport.legacyHandlerName] {
			let event = ScriptExecutionSupport.appleEvent(handler: handler, input: "in", target: "#channel")
			let name = try #require(event.paramDescriptor(forKeyword: Self.subroutineNameKeyword)?.stringValue)
			#expect(name == handler)
		}
	}

	@Test("The Apple event passes input and destination as the direct object list")
	func appleEventCarriesArguments() throws {
		let event = ScriptExecutionSupport.appleEvent(
			handler: ScriptExecutionSupport.handlerName,
			input: "hello",
			target: "#glasstual"
		)
		let arguments = try #require(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
		#expect(arguments.numberOfItems == 2)
		#expect(arguments.atIndex(1)?.stringValue == "hello")
		#expect(arguments.atIndex(2)?.stringValue == "#glasstual")
	}

	@Test("A nil destination is passed as an empty string")
	func appleEventUsesEmptyStringForMissingTarget() throws {
		let event = ScriptExecutionSupport.appleEvent(
			handler: ScriptExecutionSupport.handlerName,
			input: "",
			target: nil
		)
		let arguments = try #require(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
		#expect(arguments.atIndex(2)?.stringValue == "")
	}

	@Test("errAEEventNotHandled is recognised, whether it arrives in userInfo or as the code")
	func recognisesHandlerNotDefined() {
		let fromUserInfo = NSError(
			domain: NSOSStatusErrorDomain,
			code: 1,
			userInfo: [NSAppleScript.errorNumber: ScriptExecutionSupport.handlerNotDefinedError]
		)
		#expect(ScriptExecutionSupport.isHandlerNotDefined(fromUserInfo))

		let fromCode = NSError(
			domain: NSOSStatusErrorDomain,
			code: ScriptExecutionSupport.handlerNotDefinedError,
			userInfo: [:]
		)
		#expect(ScriptExecutionSupport.isHandlerNotDefined(fromCode))
	}

	@Test("Other AppleScript failures are not treated as a missing handler")
	func otherFailuresAreNotHandlerNotDefined() {
		let error = NSError(
			domain: NSOSStatusErrorDomain,
			code: 1,
			userInfo: [NSAppleScript.errorNumber: -2700, NSAppleScript.errorMessage: "boom"]
		)
		#expect(ScriptExecutionSupport.isHandlerNotDefined(error) == false)
	}

	@Test("An NSAppleScript error dictionary survives the trip into an NSError")
	func errorDictionaryIsPreserved() {
		let information: NSDictionary = [
			NSAppleScript.errorNumber: -2700,
			NSAppleScript.errorMessage: "boom",
		]
		let error = ScriptExecutionSupport.error(from: information)
		#expect(error.code == -2700)
		#expect(error.userInfo[NSAppleScript.errorMessage] as? String == "boom")
	}

	@Test("Both bundled scripts define the handler Glasstual asks for", arguments: ["date", "moti"])
	func bundledScriptsDefineTheHandler(named name: String) throws {
		let url = try #require(
			Bundle.main.url(forResource: name, withExtension: "scpt", subdirectory: "Bundled Scripts")
				?? Bundle.main.url(forResource: name, withExtension: "scpt")
		)
		let source = try String(
			data: #require(try? Data(contentsOf: url)),
			encoding: .macOSRoman
		)
		// The compiled script stores handler names as plain bytes in its data
		// fork, which is enough to tell the two spellings apart.
		#expect(source?.contains(ScriptExecutionSupport.handlerName) == true)
	}
}
