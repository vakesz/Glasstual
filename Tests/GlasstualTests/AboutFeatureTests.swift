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

		#expect(content.applicationName == ApplicationInfo.applicationName())
		#expect(content.versionDescription.contains(ApplicationInfo.applicationVersionShort()))
		/* The name is drawn above the version, so the version line does not
		 repeat it. */
		#expect(content.versionDescription.contains(content.applicationName) == false)
		#expect(content.acknowledgementsButtonTitle.isEmpty == false)
		#expect(content.applicationIconAccessibilityLabel.contains(content.applicationName))
	}
}
