/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
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

import CocoaExtensions
import GlasstualPluginKit
import SwiftUI

@objc(TPI_ChatFilterExtension)
final class ChatFilterPlugin: NSObject, GlasstualPlugin, PluginIncomingCommandHandling,
	PluginPreferencesProviding, PluginTextEventHandling
{
	private static let defaultsKey = "Glasstual Chat Filter Extension -> Filters"

	private var store: ChatFilterStore?
	private var engine: ChatFilterEngine?
	private var defaultsObserver: NSObjectProtocol?
	private var isSaving = false
	private var host: PluginHostContext?

	private var defaults: UserDefaults {
		guard let host else {
			preconditionFailure("The plugin host must load Chat Filters before it is used")
		}
		return host.defaults
	}

	func receivedCommand(_ event: PluginIncomingCommandEvent) -> Bool {
		engine?.receivedCommand(event) ?? true
	}

	func receivedText(_ event: PluginTextEvent) -> Bool {
		engine?.receivedText(event) ?? true
	}

	func pluginLoaded(using host: PluginHostContext) {
		self.host = host

		let store = ChatFilterStore { [weak self] filters in
			self?.save(filters)
		}
		self.store = store
		engine = ChatFilterEngine(host: host) { [weak store] in
			store?.filters ?? []
		}
		loadFilters()

		defaultsObserver = NotificationCenter.default.addObserver(
			forName: UserDefaults.didChangeNotification,
			object: defaults,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in self?.defaultsChanged() }
		}
	}

	func pluginWillUnload() {
		if let defaultsObserver {
			NotificationCenter.default.removeObserver(defaultsObserver)
		}
		defaultsObserver = nil
		engine = nil
		store = nil
		host = nil
	}

	var pluginPreferencesPane: PluginPreferencesPane? {
		guard let store, let host else { return nil }
		return PluginPreferencesPane(title: String(localized: .TPIChatFilterExtension.preferencesPaneTitle)) {
			ChatFilterPreferencesView(
				store: store,
				clients: { Self.clientOptions(from: host.clients) }
			)
		}
	}

	private func loadFilters() {
		let configurations = [PropertyListValue](
			propertyList: defaults.array(forKey: Self.defaultsKey) ?? []
		) ?? []
		store?.replaceAll(with: configurations.compactMap(\.dictionary).map(ChatFilter.init(dictionary:)))
		engine?.reloadFilterActionPerforms()
	}

	private func save(_ filters: [ChatFilter]) {
		isSaving = true
		defaults.set(filters.map(\.dictionaryValue.propertyListObject), forKey: Self.defaultsKey)
		engine?.reloadFilterActionPerforms()
	}

	private func defaultsChanged() {
		if isSaving {
			isSaving = false
		} else {
			loadFilters()
		}
	}

	private static func clientOptions(from clients: [PluginClient]) -> [ChatFilterClientOption] {
		clients.map { client in
			ChatFilterClientOption(
				id: client.identifier,
				name: client.networkName ?? client.serverAddress ?? client.userNickname,
				channels: client.channels.filter(\.isChannel).map {
					ChatFilterChannelOption(id: $0.identifier, name: $0.name)
				}
			)
		}
	}
}
