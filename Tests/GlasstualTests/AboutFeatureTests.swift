/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("About scene")
struct AboutFeatureTests {
	@Test("The about panel's copy is built from the generated application metadata")
	func contentUsesGeneratedApplicationMetadataAndLocalizedCopy() {
		let content = AboutContent.current

		#expect(content.applicationName == ApplicationInfo.applicationNameWithoutVersion())
		#expect(content.versionDescription.contains(ApplicationInfo.applicationVersionShort()))
		#expect(content.upstreamAttribution.isEmpty == false)
		#expect(content.acknowledgementsButtonTitle.isEmpty == false)
		#expect(content.applicationIconAccessibilityLabel.contains(content.applicationName))
	}
}
