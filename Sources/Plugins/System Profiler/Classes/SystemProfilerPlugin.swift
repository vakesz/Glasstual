/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import GlasstualPluginKit
import SwiftUI

@objc(TPISystemProfiler)
final class SystemProfilerPlugin: NSObject, GlasstualPlugin, PluginCommandHandling,
	PluginPreferencesProviding
{
	private var host: PluginHostContext?
	private var reports: [UUID: Task<Void, Never>] = [:]

	isolated deinit {
		for task in reports.values {
			task.cancel()
		}
	}

	var pluginPreferencesPane: PluginPreferencesPane? {
		guard let host else { return nil }
		return PluginPreferencesPane(
			title: String(localized: .BasicLanguage.preferencesPaneTitle)
		) {
			SystemProfilerPreferencesView(defaults: host.defaults)
		}
	}

	var subscribedUserInputCommands: [String] {
		["sysinfo", "memory", "uptime", "netstats", "msgcount", "diskspace", "style", "screens", "runcount", "sysmem"]
	}

	func pluginLoaded(using host: PluginHostContext) {
		pluginWillUnload()
		self.host = host
		// Only the five historically default-disabled features enter the registration domain.
		host.defaults.register(defaults: Dictionary(uniqueKeysWithValues:
			FirstPartyPluginPreferences.systemProfilerFeatures.filter(\.defaultValue)
				.map { ($0.name, $0.defaultValue) }))
	}

	func pluginWillUnload() {
		for task in reports.values {
			task.cancel()
		}
		reports.removeAll()
		host = nil
	}

	func userInputCommandInvoked(_ invocation: PluginCommandInvocation) {
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

		/* The two reports that stat filesystems and enumerate Metal devices
		 collect first and format afterwards. The task inherits the main actor,
		 so nothing but the collection leaves it, and the window keeps drawing
		 while a network mount or a sleeping GPU takes its time to answer.

		 Disk space and the time since boot are read through APIs whose
		 declared reasons (85F4.1, 35F9.1) allow showing them to the person
		 using this Mac and nothing more. `/diskspace` and `/uptime` are made of
		 those facts, so they always print locally; `/sysinfo` leaves them out
		 of the line it sends. */
		switch command {
		case "SYSINFO":
			let defaults = host.defaults
			let identifier = UUID()
			reports[identifier] = Task { [weak self] in
				defer { self?.reports.removeValue(forKey: identifier) }
				let facts = await SystemProfileInformation.hardwareFacts()
				guard !Task.isCancelled, invocation.client.isCurrentSession else { return }
				self?.output(
					SystemProfileReport.systemInformation(defaults: defaults, facts: facts, includesOnDeviceFacts: quiet),
					quiet: quiet,
					client: invocation.client,
					channel: channel
				)
			}
			return
		case "DISKSPACE":
			let identifier = UUID()
			reports[identifier] = Task { [weak self] in
				defer { self?.reports.removeValue(forKey: identifier) }
				let volumes = await SystemProfileInformation.mountedVolumeCapacities()
				guard !Task.isCancelled, invocation.client.isCurrentSession else { return }
				self?.output(
					SystemProfileReport.systemDiskSpaceInformation(volumes: volumes),
					quiet: true,
					client: invocation.client,
					channel: channel
				)
			}
			return
		case "UPTIME":
			output(
				SystemProfileReport.applicationAndSystemUptime(host: host),
				quiet: true,
				client: invocation.client,
				channel: channel
			)
			return
		default:
			break
		}

		let report: String? = switch command {
		case "NETSTATS": SystemProfileReport.systemNetworkInformation()
		case "MSGCOUNT": SystemProfileReport.applicationBandwidthStatistics(metrics: metrics)
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
