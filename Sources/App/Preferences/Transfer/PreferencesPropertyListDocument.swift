/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI
import UniformTypeIdentifiers

/// A property-list payload presented through SwiftUI's native file exporter.
/// The owning feature remains responsible for encoding and interpreting it.
struct PreferencesPropertyListDocument: FileDocument {
	static let readableContentTypes: [UTType] = [.propertyList]

	let data: Data

	init(data: Data) {
		self.data = data
	}

	init(configuration: ReadConfiguration) throws {
		guard let data = configuration.file.regularFileContents else {
			throw CocoaError(.fileReadCorruptFile)
		}
		self.data = data
	}

	func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
