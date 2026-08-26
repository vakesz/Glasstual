/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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

import Foundation
import os

@objc(ICLPluginManager)
final class InlineContentPluginManager: NSObject, @unchecked Sendable {
	@objc(sharedPluginManager)
	static let shared = InlineContentPluginManager()

	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "Plugins"
	)

	private var pluginsLoaded = false
	private var loadedPlugins: [Bundle] = []
	private var loadedModules: [AnyClass] = []

	@objc func loadBundledPlugins() {
		precondition(!pluginsLoaded, "Plugins already loaded")
		defer { pluginsLoaded = true }

		guard let pluginsURL = Bundle.main.url(forResource: "Extensions", withExtension: nil) else {
			Self.logger.error("The bundled Extensions directory is missing")
			return
		}

		loadedPlugins = loadPlugins(at: pluginsURL)
		populateModules()
	}

	@objc var modules: [AnyClass] {
		loadedModules
	}

	private func loadPlugins(at directoryURL: URL) -> [Bundle] {
		let contents: [URL]
		do {
			contents = try FileManager.default.contentsOfDirectory(
				at: directoryURL,
				includingPropertiesForKeys: nil,
				options: [.skipsHiddenFiles]
			)
		} catch {
			Self.logger.error("Failed to list plugins: \(error.localizedDescription, privacy: .public)")
			return []
		}

		return contents
			.filter { $0.pathExtension == "mediaPlugin" }
			.compactMap(loadPlugin)
	}

	private func loadPlugin(at pluginURL: URL) -> Bundle? {
		guard let bundle = Bundle(url: pluginURL) else { return nil }
		guard let principalClass = bundle.principalClass else {
			Self.logger.error(
				"Failed to load bundle '\(pluginURL.standardizedFileURL.path, privacy: .public)' because its principal class is missing"
			)
			return nil
		}
		guard principalClass.conforms(to: ICLPluginProtocol.self) else {
			Self.logger.error(
				"Failed to load bundle '\(pluginURL.standardizedFileURL.path, privacy: .public)' because its principal class does not conform to ICLPluginProtocol"
			)
			return nil
		}

		return bundle
	}

	private func populateModules() {
		if loadedPlugins.isEmpty {
			Self.logger.info("No plugins to load modules from")
			loadedModules = []
			return
		}

		var modules: [AnyClass] = []
		for plugin in loadedPlugins {
			guard let principalClass = plugin.principalClass as? ICLPluginProtocol.Type else { continue }
			modules.append(contentsOf: principalClass.modules)
		}
		loadedModules = modules
	}
}
