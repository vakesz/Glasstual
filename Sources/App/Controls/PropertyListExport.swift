// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Encoded property-list bytes for native file export. Each feature owns its encoder.
nonisolated struct PropertyListExport: Transferable {
	let data: Data

	static var transferRepresentation: some TransferRepresentation {
		DataRepresentation(exportedContentType: .propertyList) { $0.data }
	}
}
