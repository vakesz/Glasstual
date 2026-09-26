// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreTransferable
import Foundation
@testable import Glasstual
import Testing
import UniformTypeIdentifiers

struct PropertyListExportTests {
	@Test("Native export supports the requested property-list type and preserves encoded bytes")
	func exportsPropertyListBytes() async throws {
		let data = try PropertyListSerialization.data(fromPropertyList: ["name": "fixture"], format: .xml, options: 0)
		let exported = try await PropertyListExport(data: data).exported(as: .propertyList)
		#expect(exported == data)
		#expect(PropertyListExport.exportedContentTypes() == [.propertyList])
	}
}
