/* *********************************************************************
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 * Copyright (c) 2012 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *********************************************************************** */

import Foundation

/// Compiled into the app and bundled plugins; storage and registration stay with each caller.
nonisolated enum FirstPartyPluginPreferences { // nonisolated: value
	struct BooleanDefinition: Sendable {
		let name: String
		let defaultValue: Bool
	}

	/** Posted when a preference is written through `TextualUserDefaults`, which
	 includes a configuration import.

	 The app spells this as `Notification.Name.textualUserDefaultsDidChange`. It
	 is declared here because a plugin bundle does not compile the app's own
	 defaults wrapper, and a second copy of the string in each bundle is a name
	 that can drift out of step with the one being posted. */
	static let defaultsDidChangeNotification = Notification.Name(
		"TPCPreferencesUserDefaultsDidChangeNotification"
	)

	static let chatFilters = "Glasstual Chat Filter Extension -> Filters"
	static let caffeinePreventSleep = BooleanDefinition(
		name: "Private Extension Store -> Caffeine Extension -> Prevent Sleep", defaultValue: false
	)
	static let smileyServiceEnabled = BooleanDefinition(
		name: "Smiley Converter Extension -> Enable Service", defaultValue: false
	)
	static let smileyExtraEmoticons = BooleanDefinition(
		name: "Smiley Converter Extension -> Enable Extra Emoticons", defaultValue: false
	)

	static let systemProfilerFeatures = SystemProfilerFeature.allCases
		.sorted { $0.rawValue < $1.rawValue }.map(\.disabledPreference)
}

nonisolated enum SystemProfilerFeature: String, CaseIterable, Identifiable, Sendable { // nonisolated: value
	case cpuModel = "CPU Model"
	case memoryInformation = "Memory Information"
	case systemUptime = "System Uptime"
	case diskInformation = "Disk Information"
	case gpuModel = "GPU Model"
	case screenResolution = "Screen Resolution"
	case operatingSystemVersion = "OS Version"

	var id: Self {
		self
	}

	var disabledPreference: FirstPartyPluginPreferences.BooleanDefinition {
		let defaultValue = switch self {
		case .cpuModel, .operatingSystemVersion: false
		case .memoryInformation, .systemUptime, .diskInformation, .gpuModel, .screenResolution: true
		}
		return FirstPartyPluginPreferences.BooleanDefinition(
			name: "System Profiler Extension -> Feature Disabled -> \(rawValue)", defaultValue: defaultValue
		)
	}
}
