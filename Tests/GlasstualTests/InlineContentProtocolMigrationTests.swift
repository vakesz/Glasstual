/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import InlineContentKit
import XCTest

final class InlineContentProtocolMigrationTests: XCTestCase {
	func testXPCProtocolRuntimeNamesRemainStable() {
		XCTAssertEqual(NSStringFromProtocol(InlineContentServerProtocol.self), "ICLInlineContentServerProtocol")
		XCTAssertEqual(NSStringFromProtocol(InlineContentClientProtocol.self), "ICLInlineContentClientProtocol")
	}

	func testXPCSelectorsRemainCompatibleWithExistingProcesses() {
		XCTAssertEqual(
			NSStringFromSelector(
				#selector((any InlineContentServerProtocol).warmServiceByLoadingPlugins(atLocations:))
			),
			"warmServiceByLoadingPluginsAtLocations:"
		)
		XCTAssertEqual(
			NSStringFromSelector(#selector((any InlineContentServerProtocol).warmServiceByRegistering(defaults:))),
			"warmServiceByRegisteringDefaults:"
		)
		XCTAssertEqual(
			NSStringFromSelector(#selector((any InlineContentServerProtocol).process(_:))),
			"processPayload:"
		)
		XCTAssertEqual(
			NSStringFromSelector(#selector((any InlineContentClientProtocol).processingPayloadSucceeded(_:))),
			"processingPayloadSucceeded:"
		)
	}

	func testAppAdapterConformsToNativeClientProtocol() {
		XCTAssertTrue(LogControllerInlineMediaService.conforms(to: InlineContentClientProtocol.self))
		XCTAssertEqual(NSStringFromClass(InlineContentPayload.self), "ICLPayload")
	}

	func testInlineContentKitPreservesLegacyRuntimeClassNames() {
		let expectedNames: [(AnyClass, String)] = [
			(InlineContentPayload.self, "ICLPayload"),
			(InlineContentPayloadMutable.self, "ICLPayloadMutable"),
			(InlineContentModule.self, "ICLInlineContentModule"),
			(MediaAssessment.self, "ICLMediaAssessment"),
			(MediaAssessmentMutable.self, "ICLMediaAssessmentMutable"),
			(MediaAssessor.self, "ICLMediaAssessor"),
			(InlineHTMLFoundation.self, "ICMInlineHTMLFoundation"),
			(InlineHTMLModule.self, "ICMInlineHTML"),
			(InlineImageFoundation.self, "ICMInlineImageFoundation"),
			(InlineImageModule.self, "ICMInlineImage"),
			(InlineVideoFoundation.self, "ICMInlineVideoFoundation"),
			(InlineVideoModule.self, "ICMInlineVideo"),
			(InlineGifVideoModule.self, "ICMInlineGifVideo"),
		]

		for classReferenceAndName in expectedNames {
			let classReference: AnyClass = classReferenceAndName.0
			let expectedName = classReferenceAndName.1

			XCTAssertEqual(NSStringFromClass(classReference), expectedName)
		}
	}
}
