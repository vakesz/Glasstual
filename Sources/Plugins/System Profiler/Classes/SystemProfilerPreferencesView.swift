/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
		case .cpuModel: SystemProfilerLocalization.string(.BasicLanguage.includeCpuModel)
		case .memoryInformation: SystemProfilerLocalization.string(.BasicLanguage.includeSystemMemory)
		case .systemUptime: SystemProfilerLocalization.string(.BasicLanguage.includeSystemUptime)
		case .diskInformation: SystemProfilerLocalization.string(.BasicLanguage.includeDiskInformation)
		case .gpuModel: SystemProfilerLocalization.string(.BasicLanguage.includeGraphicsCard)
		case .screenResolution: SystemProfilerLocalization.string(.BasicLanguage.includeScreenResolution)
		case .operatingSystemVersion:
			SystemProfilerLocalization.string(.BasicLanguage.includeOperatingSystemVersion)
		}
	}
}

struct SystemProfilerPreferencesView: View {
	let defaults: UserDefaults

	var body: some View {
		Form {
			Section {
				Text(SystemProfilerLocalization.string(.BasicLanguage.sysinfoOptionsExplanation))
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
