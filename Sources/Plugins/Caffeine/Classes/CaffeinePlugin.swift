/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
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

@objc(TPI_Caffeine)
final class CaffeinePlugin: NSObject, GlasstualPlugin, PluginPreferencesProviding {
	private static let preventSleepPreference = "Private Extension Store -> Caffeine Extension -> Prevent Sleep"
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "Extension['\(Bundle(for: CaffeinePlugin.self).object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Caffeine")']"
	)

	@IBOutlet private var preferencesPane: NSView?

	private var activity: NSObjectProtocol?
	private var connectionObservation: PluginObservation?
	private var host: PluginHostContext?

	private var shouldPreventSleepWhenConnected: Bool {
		host?.defaults.bool(forKey: Self.preventSleepPreference) == true
	}

	private var bundle: Bundle {
		Bundle(for: CaffeinePlugin.self)
	}

	private func disableSleep() {
		guard activity == nil else { return }
		activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Disable sleep mode")
		Self.logger.info("Disabled sleep mode")
	}

	private func enableSleep() {
		guard let activity else { return }
		ProcessInfo.processInfo.endActivity(activity)
		self.activity = nil
		Self.logger.info("Enabled sleep mode")
	}

	private func updateSleepState(hasConnectedClient: Bool) {
		if shouldPreventSleepWhenConnected, hasConnectedClient {
			disableSleep()
		} else {
			enableSleep()
		}
	}

	private func refreshSleepState() {
		updateSleepState(hasConnectedClient: host?.clients.contains(where: \.isLoggedIn) == true)
	}

	@IBAction private func toggledDisableSleepModeWhileConnected(_: Any?) {
		refreshSleepState()
	}

	func pluginLoaded(using host: PluginHostContext) {
		self.host = host
		if bundle.loadNibNamed("TPI_Caffeine", owner: self, topLevelObjects: nil) == false {
			Self.logger.error("Failed to load TPI_Caffeine.xib; the preferences pane is unavailable")
		}
		connectionObservation = host.observeConnectionState { [weak self] hasConnectedClient in
			self?.updateSleepState(hasConnectedClient: hasConnectedClient)
		}
	}

	func pluginWillUnload() {
		connectionObservation?.cancel()
		connectionObservation = nil
		host = nil
		enableSleep()
	}

	var pluginPreferencesPaneMenuItemName: String {
		String(localized: .BasicLanguage.sleepModeManagement)
	}

	var pluginPreferencesPaneView: NSView? {
		preferencesPane
	}
}
