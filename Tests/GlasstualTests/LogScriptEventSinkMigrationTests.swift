/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Log script event sink")
struct LogScriptEventSinkMigrationTests {
	@Test("A line identifier keeps its established normalization")
	func lineIdentifiersKeepEstablishedNormalization() {
		#expect(TVCLogScriptEventSink.standardizeLineNumber("line-42") == "42")
		#expect(TVCLogScriptEventSink.standardizeLineNumber("42") == "42")
		#expect(
			TVCLogScriptEventSink.standardizeLineNumbers(["line-a", "b", "line-c"])
				== ["a", "b", "c"]
		)
	}

	@Test("Payload conversion drops null and unescapes HTML")
	func commonPayloadConversionPreservesNullAndHTMLSemantics() {
		#expect(TVCLogScriptEventSink.objectValueToCommon(NSNull()) == nil)
		#expect(TVCLogScriptEventSink.objectValueToCommon("Tom &amp; Jerry") as? String == "Tom & Jerry")
		#expect(TVCLogScriptEventSink.objectValueToCommon(NSNumber(value: 7)) as? NSNumber == 7)
	}
}
