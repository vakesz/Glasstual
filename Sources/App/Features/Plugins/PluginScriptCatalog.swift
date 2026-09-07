/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

public nonisolated struct PluginScript: Equatable, Sendable { // nonisolated: value
	public enum Kind: Sendable {
		case appleScript
		case unixExecutable
	}

	public enum Origin: Sendable {
		case custom
		case bundled
	}

	public let url: URL
	public let kind: Kind
	public let origin: Origin

	init?(url: URL, origin: Origin) {
		guard url.isFileURL,
		      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
		      values.isRegularFile == true, values.isSymbolicLink != true
		else { return nil }
		if url.pathExtension.lowercased() == "scpt" {
			kind = .appleScript
		} else if FileManager.default.isExecutableFile(atPath: url.path) {
			kind = .unixExecutable
		} else {
			return nil
		}
		self.url = url
		self.origin = origin
	}
}

nonisolated struct PluginScriptCatalog: Sendable { // nonisolated: value
	var commandsByName: [String: PluginScript] = [:]
	var customScriptsURL: URL?

	static func discover(customURL: URL?, bundledURL: URL, forbiddenCommands: Set<String>) -> Self {
		var result = Self(customScriptsURL: customURL)
		let locations: [(URL?, PluginScript.Origin)] = [(customURL, .custom), (bundledURL, .bundled)]
		for (directory, origin) in locations {
			guard let directory,
			      let entries = try? FileManager.default.contentsOfDirectory(
			      	at: directory,
			      	includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
			      	options: [.skipsHiddenFiles]
			      ) else { continue }
			// Custom commands win; within one directory the literal filename wins.
			for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
				let command = url.deletingPathExtension().lastPathComponent.lowercased()
				guard !command.isEmpty, !forbiddenCommands.contains(command),
				      result.commandsByName[command] == nil,
				      let script = PluginScript(url: url, origin: origin)
				else { continue }
				result.commandsByName[command] = script
			}
		}
		return result
	}
}
