/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("File transfer dialog socket")
struct FileTransferDialogSocketMigrationTests {
	@Test("The error factory carries the domain, the code and the description through")
	func errorFactoryPreservesDomainCodeAndDescription() {
		let error = FileTransferDialogSocket.error(
			withCode: .writeTimeout,
			description: "Write operation timed out"
		)

		#expect(error.domain == TDCFileTransferDialogSocketErrorDomain)
		#expect(error.code == FileTransferDialogSocketError.writeTimeout.rawValue)
		#expect(error.localizedDescription == "Write operation timed out")
	}
}
