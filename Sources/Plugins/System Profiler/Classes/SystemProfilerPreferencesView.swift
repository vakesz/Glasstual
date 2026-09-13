/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2012 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

@MainActor
extension SystemProfilerFeature {
	var title: String {
		switch self {
		case .cpuModel: String(localized: .BasicLanguage.includeCpuModel)
		case .memoryInformation: String(localized: .BasicLanguage.includeSystemMemory)
		case .systemUptime: String(localized: .BasicLanguage.includeSystemUptime)
		case .diskInformation: String(localized: .BasicLanguage.includeDiskInformation)
		case .gpuModel: String(localized: .BasicLanguage.includeGraphicsCard)
		case .screenResolution: String(localized: .BasicLanguage.includeScreenResolution)
		case .operatingSystemVersion: String(localized: .BasicLanguage.includeOperatingSystemVersion)
		}
	}
}

struct SystemProfilerPreferencesView: View {
	let defaults: UserDefaults

	var body: some View {
		Form {
			Section {
				Text(String(localized: .BasicLanguage.sysinfoOptionsExplanation))
					.fixedSize(horizontal: false, vertical: true)
			}

			Section {
				ForEach(SystemProfilerFeature.allCases) { feature in
					SystemProfilerFeatureToggle(feature: feature, defaults: defaults)
				}
			}
		}
		.formStyle(.grouped)
	}
}

private struct SystemProfilerFeatureToggle: View {
	let feature: SystemProfilerFeature
	@AppStorage private var isDisabled: Bool

	init(feature: SystemProfilerFeature, defaults: UserDefaults) {
		self.feature = feature
		_isDisabled = AppStorage(
			wrappedValue: feature.disabledPreference.defaultValue,
			feature.disabledPreference.name,
			store: defaults
		)
	}

	/// The switch says what is included; the stored key says what is left out,
	/// because that is the spelling the reports have always been written with.
	private var isEnabled: Binding<Bool> {
		Binding(
			get: { isDisabled == false },
			set: { isDisabled = $0 == false }
		)
	}

	var body: some View {
		Toggle(feature.title, isOn: isEnabled)
			.toggleStyle(.switch)
	}
}
