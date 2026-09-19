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
final class ScriptCatalogStore {
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

	var customScriptsURL: URL? {
		catalog.customScriptsURL
	}

	/** Makes the user's Custom Scripts folder reachable from the group container.

	 The folder the user drops scripts into lives in the application's own
	 Application Support directory; the group container is what the rest of the
	 suite can see. A symbolic link is planted once, and only when there is
	 nothing at the destination already, so a real folder someone put there is
	 never replaced. */
	@concurrent
	static func linkCustomScriptsIntoGroupContainer() async {
		guard let sourceURL = ApplicationPaths.customScriptsURL,
		      let destinationRoot = ApplicationPaths.groupContainerApplicationSupportURL
		else {
			return
		}

		let destinationURL = destinationRoot.appendingPathComponent("Custom Scripts", isDirectory: true)
		let fileManager = FileManager.default

		guard fileManager.fileExists(at: sourceURL),
		      fileManager.fileExists(at: destinationURL) == false
		else {
			return
		}

		try? fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
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

/// The dispatch path's view of the catalog: the command dispatcher asks whether
/// a script claims a command, and the answer runs it. Nothing under `Chat/` or
/// `Protocol/` names a script, a path or a language.
extension ScriptCatalogStore: UserScriptRunning {
	func runScript(forOutgoingCommand command: String, input: String, target: String?, on session: ServerSession) -> Bool {
		guard let script = catalog.commandsByName[command.lowercased()] else {
			return false
		}

		session.execute(script, input: input, target: target)

		return true
	}
}
