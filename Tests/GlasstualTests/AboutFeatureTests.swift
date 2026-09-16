/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("About scene")
struct AboutFeatureTests {
	@Test("The version line names the build only when it differs from the version")
	func versionDescriptionNamesTheBuildOnlyWhenItDiffers() {
		let name = ApplicationInfo.applicationName()

		let withBuild = AboutView.versionDescription(version: "1.2.1", build: "121")
		#expect(withBuild.contains("1.2.1"))
		#expect(withBuild.contains("121"))

		let withoutBuild = AboutView.versionDescription(version: "1.2.1", build: "1.2.1")
		#expect(withoutBuild.contains("1.2.1"))
		/* The name is drawn above the version, so the version line does not
		 repeat it. */
		#expect(withoutBuild.contains(name) == false)
		#expect(withBuild.contains(name) == false)
	}
}
