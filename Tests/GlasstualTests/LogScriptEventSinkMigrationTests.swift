/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class LogScriptEventSinkMigrationTests: XCTestCase {
	@MainActor
	func testRegisteredJavaScriptHandlersKeepObjectiveCSelectors() {
		let sink = TVCLogScriptEventSink(webView: nil)
		let handlerNames = [
			"appearance", "channelIsActive", "channelMemberCount", "channelName",
			"channelNameDoubleClicked", "displayContextMenu", "copySelectionWhenPermitted",
			"inlineMediaEnabledForView", "loadInlineMedia", "localUserHostmask", "localUserNickname",
			"logToConsole", "networkName", "nicknameColorStyleHash", "nicknameDoubleClicked",
			"notifyLinesAddedToView", "notifyLinesRemovedFromView", "notifyJumpToLineCallback",
			"printDebugInformation", "printDebugInformationToConsole", "renderMessagesBefore",
			"renderMessagesAfter", "renderMessagesInRange", "renderMessageWithSiblings", "renderTemplate",
			"retrievePreferencesWithMethodName", "sendPluginPayload", "serverAddress", "serverChannelCount",
			"serverIsConnected", "setChannelName", "setNickname", "setLineContext", "setSelection",
			"setURLAddress", "sidebarInversionIsEnabled", "styleSettingsRetrieveValue",
			"styleSettingsSetValue", "topicBarDoubleClicked", "finishedLayingOutView",
		]

		for handlerName in handlerNames {
			let selector = NSSelectorFromString("\(handlerName):inWebView:")
			XCTAssertTrue(sink.responds(to: selector), "Missing JavaScript selector \(selector)")
		}
	}

	@MainActor
	func testLineIdentifiersKeepEstablishedNormalization() {
		XCTAssertEqual(TVCLogScriptEventSink.standardizeLineNumber("line-42"), "42")
		XCTAssertEqual(TVCLogScriptEventSink.standardizeLineNumber("42"), "42")
		XCTAssertEqual(
			TVCLogScriptEventSink.standardizeLineNumbers(["line-a", "b", "line-c"]),
			["a", "b", "c"]
		)
	}

	@MainActor
	func testCommonPayloadConversionPreservesNullAndHTMLSemantics() {
		XCTAssertNil(TVCLogScriptEventSink.objectValueToCommon(NSNull()))
		XCTAssertEqual(TVCLogScriptEventSink.objectValueToCommon("Tom &amp; Jerry") as? String, "Tom & Jerry")
		XCTAssertEqual(TVCLogScriptEventSink.objectValueToCommon(NSNumber(value: 7)) as? NSNumber, 7)
	}
}
