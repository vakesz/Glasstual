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

@objc(TPISystemProfiler)
final class SystemProfilerPlugin: NSObject, THOPluginProtocol, @unchecked Sendable {
	private static let defaultPreferences = [
		"System Profiler Extension -> Feature Disabled -> GPU Model": true,
		"System Profiler Extension -> Feature Disabled -> Disk Information": true,
		"System Profiler Extension -> Feature Disabled -> System Uptime": true,
		"System Profiler Extension -> Feature Disabled -> Memory Information": true,
		"System Profiler Extension -> Feature Disabled -> Screen Resolution": true,
	]

	@IBOutlet private var preferencePaneView: NSView!

	var pluginPreferencesPaneView: NSView {
		preferencePaneView
	}

	var pluginPreferencesPaneMenuItemName: String {
		SystemProfilerLocalization.string("dff-13")
	}

	var subscribedUserInputCommands: [String] {
		["sysinfo", "memory", "uptime", "netstats", "msgcount", "diskspace", "style", "screens", "runcount", "sysmem"]
	}

	func pluginLoadedIntoMemory() {
		TPCPreferencesUserDefaults.shared().register(defaults: Self.defaultPreferences)
		DispatchQueue.main.syncIfNeeded {
			Bundle(for: SystemProfilerPlugin.self).loadNibNamed("TPISystemProfiler", owner: self, topLevelObjects: nil)
		}
	}

	func userInputCommandInvoked(on client: IRCClient, command: String, messageString: String) {
		let client = MainActorTransfer(value: client)
		Task { @MainActor [weak self] in
			self?.handleCommand(command, message: messageString, client: client.value)
		}
	}

	@MainActor
	private func handleCommand(_ command: String, message: String, client: IRCClient) {
		guard let channel = NSObject.masterController().mainWindow.selectedChannel else { return }
		let quiet = message.caseInsensitiveCompare("quiet") == .orderedSame

		if command == "MEMORY" {
			output(SystemProfileReport.applicationMemoryUsage(), quiet: quiet, client: client, channel: channel)
			return
		}

		let report: String? = switch command {
		case "SYSINFO": SystemProfileReport.systemInformation()
		case "UPTIME": SystemProfileReport.applicationAndSystemUptime()
		case "NETSTATS": SystemProfileReport.systemNetworkInformation()
		case "MSGCOUNT": SystemProfileReport.applicationBandwidthStatistics()
		case "DISKSPACE": SystemProfileReport.systemDiskSpaceInformation()
		case "STYLE": SystemProfileReport.applicationActiveStyle()
		case "SCREENS": SystemProfileReport.systemDisplayInformation()
		case "RUNCOUNT": SystemProfileReport.applicationRuntimeStatistics()
		case "SYSMEM": SystemProfileReport.systemMemoryInformation()
		default: nil
		}
		if let report {
			output(report, quiet: quiet, client: client, channel: channel)
		}
	}

	private func output(_ message: String, quiet: Bool, client: IRCClient, channel: IRCChannel) {
		for line in message.components(separatedBy: .newlines) {
			if quiet {
				client.printDebugInformation(line, in: channel)
			} else {
				client.sendPrivmsg(line, to: channel)
			}
		}
	}
}

private extension DispatchQueue {
	func syncIfNeeded(_ work: () -> Void) {
		if Thread.isMainThread {
			work()
		} else {
			sync(execute: work)
		}
	}
}

private struct MainActorTransfer<Value>: @unchecked Sendable {
	let value: Value
}
