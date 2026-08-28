/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2012 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
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
 *
 *********************************************************************** */

import AppKit
import GlasstualPluginKit
import os

@objc(TPISystemProfiler)
final class SystemProfilerPlugin: NSObject, GlasstualPlugin, PluginCommandHandling,
	PluginPreferencesProviding
{
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Extension['System Profiler']"
	)

	private static let defaultPreferences = [
		"System Profiler Extension -> Feature Disabled -> GPU Model": true,
		"System Profiler Extension -> Feature Disabled -> Disk Information": true,
		"System Profiler Extension -> Feature Disabled -> System Uptime": true,
		"System Profiler Extension -> Feature Disabled -> Memory Information": true,
		"System Profiler Extension -> Feature Disabled -> Screen Resolution": true,
	]

	@IBOutlet private var preferencePaneView: NSView?
	private var host: PluginHostContext?

	var pluginPreferencesPaneView: NSView? {
		preferencePaneView
	}

	var pluginPreferencesPaneMenuItemName: String {
		SystemProfilerLocalization.string(.BasicLanguage.preferencesPaneTitle)
	}

	var subscribedUserInputCommands: [String] {
		["sysinfo", "memory", "uptime", "netstats", "msgcount", "diskspace", "style", "screens", "runcount", "sysmem"]
	}

	func pluginLoaded(using host: PluginHostContext) {
		self.host = host
		host.defaults.register(defaults: Self.defaultPreferences)
		let bundle = Bundle(for: SystemProfilerPlugin.self)
		if bundle.loadNibNamed("TPISystemProfiler", owner: self, topLevelObjects: nil) == false {
			Self.logger.error("Failed to load TPISystemProfiler.xib; the preferences pane is unavailable")
		}
	}

	func userInputCommandInvoked(_ invocation: PluginCommandInvocation) {
		handleCommand(invocation)
	}

	private func handleCommand(_ invocation: PluginCommandInvocation) {
		guard let channel = invocation.selectedChannel, let host else { return }
		let command = invocation.command
		let quiet = invocation.message.caseInsensitiveCompare("quiet") == .orderedSame
		let metrics = host.applicationMetrics

		if command == "MEMORY" {
			output(
				SystemProfileReport.applicationMemoryUsage(metrics: metrics),
				quiet: quiet,
				client: invocation.client,
				channel: channel
			)
			return
		}

		let report: String? = switch command {
		case "SYSINFO": SystemProfileReport.systemInformation(defaults: host.defaults)
		case "UPTIME": SystemProfileReport.applicationAndSystemUptime(host: host)
		case "NETSTATS": SystemProfileReport.systemNetworkInformation()
		case "MSGCOUNT": SystemProfileReport.applicationBandwidthStatistics(metrics: metrics)
		case "DISKSPACE": SystemProfileReport.systemDiskSpaceInformation()
		case "STYLE": SystemProfileReport.applicationActiveStyle(metrics: metrics, host: host)
		case "SCREENS": SystemProfileReport.systemDisplayInformation()
		case "RUNCOUNT": SystemProfileReport.applicationRuntimeStatistics(host: host)
		case "SYSMEM": SystemProfileReport.systemMemoryInformation()
		default: nil
		}
		if let report {
			output(report, quiet: quiet, client: invocation.client, channel: channel)
		}
	}

	private func output(_ message: String, quiet: Bool, client: PluginClient, channel: PluginChannel) {
		for line in message.components(separatedBy: .newlines) {
			if quiet {
				client.printDebug(line, in: channel)
			} else {
				client.sendPrivateMessage(line, to: channel)
			}
		}
	}
}
