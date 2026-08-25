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
import os

@objc(TPI_Caffeine)
final class CaffeinePlugin: NSObject, THOPluginProtocol, @unchecked Sendable {
	private static let preventSleepPreference = "Private Extension Store -> Caffeine Extension -> Prevent Sleep"

	@IBOutlet private var preferencesPane: NSView!

	private var activity: NSObjectProtocol?
	private var clientObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
	private var clientListObserver: NSObjectProtocol?

	private var shouldPreventSleepWhenConnected: Bool {
		TPCPreferencesUserDefaults.shared().bool(forKey: Self.preventSleepPreference)
	}

	private var bundle: Bundle {
		Bundle(for: CaffeinePlugin.self)
	}

	private func disableSleep() {
		guard activity == nil else { return }
		activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Disable sleep mode")
		os_log("Disabled sleep mode", log: _THOPluginLoggingSubsystemForBundle(bundle), type: .default)
	}

	private func enableSleep() {
		guard let activity else { return }
		ProcessInfo.processInfo.endActivity(activity)
		self.activity = nil
		os_log("Enabled sleep mode", log: _THOPluginLoggingSubsystemForBundle(bundle), type: .default)
	}

	private func updateSleepState() {
		let hasConnectedClient = clientObservations.keys.contains { identifier in
			observedClients.first { ObjectIdentifier($0) == identifier }?.isLoggedIn == true
		}
		if hasConnectedClient {
			disableSleep()
		} else {
			enableSleep()
		}
	}

	private var observedClients: [IRCClient] {
		NSObject.masterController().world.clientList
	}

	private func rebuildObservedClients() {
		guard shouldPreventSleepWhenConnected else {
			clientObservations.removeAll()
			enableSleep()
			return
		}

		let clients = observedClients
		let currentIdentifiers = Set(clients.map(ObjectIdentifier.init))
		clientObservations = clientObservations.filter { currentIdentifiers.contains($0.key) }

		for client in clients where clientObservations[ObjectIdentifier(client)] == nil {
			clientObservations[ObjectIdentifier(client)] = client
				.observe(\.isLoggedIn, options: [.new]) { [weak self] _, _ in
					self?.updateSleepState()
				}
		}

		updateSleepState()
	}

	@IBAction private func toggledDisableSleepModeWhileConnected(_: Any?) {
		rebuildObservedClients()
	}

	func pluginLoadedIntoMemory() {
		bundle.loadNibNamed("TPI_Caffeine", owner: self, topLevelObjects: nil)
		clientListObserver = NotificationCenter.default.addObserver(
			forName: .IRCWorldClientListWasModified,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.rebuildObservedClients()
		}
		rebuildObservedClients()
	}

	func pluginWillBeUnloadedFromMemory() {
		if let clientListObserver {
			NotificationCenter.default.removeObserver(clientListObserver)
		}
		clientListObserver = nil
		clientObservations.removeAll()
		enableSleep()
	}

	var pluginPreferencesPaneMenuItemName: String {
		bundle.localizedString(forKey: "xqp-6g", value: nil, table: "BasicLanguage")
	}

	var pluginPreferencesPaneView: NSView {
		preferencesPane
	}
}
