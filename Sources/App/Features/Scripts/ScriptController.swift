// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** The user scripts the application can run as commands.

 A scan reads the bundled scripts folder and the user's own, off the main
 actor, and publishes what it found here. Everything that reads the catalog —
 command dispatch, nickname completion, Settings — is main-actor, so the
 controller is too, and a scan is an `await` rather than a lock. */
@MainActor
final class ScriptController {
	private var catalog = ScriptCatalog()

	/** Which scan the published catalog came from.

	 Two scans can be in flight at once — the one at launch and one a Finder
	 edit started — and they can land in either order, so a scan whose
	 generation is no longer the newest reserved one has been overtaken and its
	 catalog is dropped. */
	private var generation = 0

	/// Rebuilds the catalog without blocking command entry or Settings.
	/// Launch, activation and a completed import all call this, so Finder edits
	/// are picked up while the application stays open.
	func refreshCommands() {
		generation += 1
		let reserved = generation
		Task { [weak self] in
			let scanned = await Self.scan()
			self?.publish(scanned, generation: reserved)
		}
	}

	private func publish(_ catalog: ScriptCatalog, generation: Int) {
		guard generation == self.generation else { return }
		self.catalog = catalog
	}

	var commandNames: [String] {
		catalog.commandsByName.keys.sorted()
	}

	func script(at url: URL) -> UserScript? {
		catalog.commandsByName.values.first { $0.url == url }
	}

	var customScriptsURL: URL? {
		catalog.customScriptsURL
	}

	/** The user script an outgoing command runs, if any.

	 A command the client has no built-in handler for goes to the server as
	 written unless a script claims it. */
	func scriptPath(forOutgoingCommand command: String) -> String? {
		catalog.commandsByName[command.lowercased()]?.url.path
	}

	@concurrent
	private static func scan() async -> ScriptCatalog {
		ScriptCatalog.discover(
			customURL: ApplicationPaths.customScriptsURL,
			bundledURL: ApplicationPaths.bundledScriptsURL,
			forbiddenCommands: Set(forbiddenCommandNames())
		)
	}

	private nonisolated static func forbiddenCommandNames() -> [String] { // nonisolated: pure
		BundleResources.array(
			fromResources: StaticStoreResource.name,
			key: StaticStoreResource.forbiddenScriptCommandsKey
		)?.compactMap(\.string) ?? []
	}
}
