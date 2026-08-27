/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class HistoricLogProtocolMigrationTests: XCTestCase {
	func testXPCProtocolRuntimeNamesRemainStable() {
		XCTAssertEqual(NSStringFromProtocol(HistoricLogServerProtocol.self), "HLSHistoricLogServerProtocol")
		XCTAssertEqual(NSStringFromProtocol(HistoricLogClientProtocol.self), "HLSHistoricLogClientProtocol")
	}

	func testXPCSelectorsRemainCompatibleWithExistingProcesses() {
		let selectors = [
			#selector((any HistoricLogServerProtocol).openDatabase(inDirectory:withCompletionBlock:)),
			#selector((any HistoricLogServerProtocol).writeLogLine(_:)),
			#selector((any HistoricLogServerProtocol).saveData(completionBlock:)),
			#selector((any HistoricLogServerProtocol).forgetView(_:)),
			#selector((any HistoricLogServerProtocol).resetData(forView:)),
			#selector((any HistoricLogServerProtocol).setMaximumLineCount(_:)),
			#selector((any HistoricLogClientProtocol).willDeleteUniqueIdentifiers(_:inView:)),
		].map(NSStringFromSelector)

		XCTAssertEqual(
			selectors,
			[
				"openDatabaseInDirectory:withCompletionBlock:",
				"writeLogLine:",
				"saveDataWithCompletionBlock:",
				"forgetView:",
				"resetDataForView:",
				"setMaximumLineCount:",
				"willDeleteUniqueIdentifiers:inView:",
			]
		)
	}

	func testFetchSelectorsRemainCompatibleWithExistingProcesses() {
		let selectors = [
			"fetchEntriesForView:ascending:fetchLimit:limitToDate:withCompletionBlock:",
			"fetchEntriesForView:withUniqueIdentifier:beforeFetchLimit:afterFetchLimit:limitToDate:withCompletionBlock:",
			"fetchEntriesForView:beforeUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:",
			"fetchEntriesForView:afterUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:",
			"fetchEntriesForView:afterUniqueIdentifier:beforeUniqueIdentifier:fetchLimit:withCompletionBlock:",
		]

		for selector in selectors {
			XCTAssertNotNil(
				protocol_getMethodDescription(
					HistoricLogServerProtocol.self,
					NSSelectorFromString(selector),
					true,
					true
				).name,
				selector
			)
		}
	}
}
