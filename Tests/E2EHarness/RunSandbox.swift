import Foundation

/// The Debug application under test and where its sandbox keeps things.
struct AppBundle {
	let url: URL
	let executable: URL
	let bundleIdentifier: String
	let groupIdentifier: String

	init(url: URL) throws {
		guard let bundle = Bundle(url: url), let executable = bundle.executableURL,
		      FileManager.default.isExecutableFile(atPath: executable.path),
		      let bundleIdentifier = bundle.bundleIdentifier,
		      let groupIdentifier = bundle.object(forInfoDictionaryKey: "GlasstualApplicationGroupIdentifier") as? String
		else {
			throw HarnessFailure.setup("No Debug Glasstual.app at \(url.path). Run make e2e, which builds it first.")
		}
		let binary = try Data(contentsOf: executable, options: .mappedIfSafe)
		guard binary.range(of: Data("GLASSTUAL_E2E".utf8)) != nil,
		      binary.range(of: Data("GLASSTUAL_UI_REVIEW_PREFERENCES".utf8)) != nil
		else {
			throw HarnessFailure.setup("\(url.path) is not a Debug build with the end-to-end hooks. Run make e2e.")
		}
		self.url = url
		self.executable = executable
		self.bundleIdentifier = bundleIdentifier
		self.groupIdentifier = groupIdentifier
	}

	private static var home: URL {
		FileManager.default.homeDirectoryForCurrentUser
	}

	/// The sandbox container's `Data/Library`.
	var containerLibrary: URL {
		Self.home.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library", isDirectory: true)
	}

	var groupContainer: URL {
		Self.home.appendingPathComponent("Library/Group Containers/\(groupIdentifier)", isDirectory: true)
	}
}

/** Everything one scenario's application may write, under one token.

 The token names the defaults suite, the review directory (in the group
 container and in Application Support), the Downloads folder DCC writes to and
 the keychain service prefix, so no two runs, and no run and the person's own
 copy of the application, share any of them. The application removes all of
 it when its last launch quits; ``removeLeftovers()`` removes what a crash left. */
struct RunSandbox {
	let token: String
	let app: AppBundle

	init(scenario: String, app: AppBundle) {
		let unique = UUID().uuidString.lowercased().prefix(8)
		token = "e2e-\(scenario)-\(unique)"
		self.app = app
	}

	var suite: String {
		app.bundleIdentifier + "." + token
	}

	/// What `KeychainStore.isolatedServicePrefix` is for this run.
	var keychainPrefix: String {
		"glasstual.tests.\(token)."
	}

	var groupDirectory: URL {
		app.groupContainer.appendingPathComponent("UI Reviews/\(token)", isDirectory: true)
	}

	var supportDirectory: URL {
		app.containerLibrary.appendingPathComponent("Application Support/Glasstual/UI Reviews/\(token)", isDirectory: true)
	}

	var preferencesFile: URL {
		app.containerLibrary.appendingPathComponent("Preferences/\(suite).plist")
	}

	/// Where the application saves DCC downloads in this run.
	var downloads: URL {
		groupDirectory.appendingPathComponent("Downloads", isDirectory: true)
	}

	/// Where the application's file dialogs open in this run.
	var transfers: URL {
		groupDirectory.appendingPathComponent("Transfers", isDirectory: true)
	}

	/// The application's environment: only the basics of the login, the review
	/// overrides and the end-to-end mode. Nothing from the harness's own
	/// environment leaks into the application under test.
	func environment(seed: Data?, keepsState: Bool) -> [String: String] {
		var environment = ProcessInfo.processInfo.environment.filter {
			["HOME", "USER", "LOGNAME", "PATH", "TMPDIR"].contains($0.key)
		}
		environment["GLASSTUAL_UI_REVIEW_SUITE"] = suite
		environment["GLASSTUAL_UI_REVIEW_DIRECTORY"] = token
		environment["GLASSTUAL_E2E"] = keepsState ? "keep" : "1"
		if let seed {
			environment["GLASSTUAL_UI_REVIEW_PREFERENCES"] = seed.base64EncodedString()
		}
		return environment
	}

	/// What is still on disk for this run. The suite is read through
	/// `cfprefsd`, which is where the application removed it.
	func leftovers() async -> [String] {
		var found: [String] = []
		for directory in [groupDirectory, supportDirectory] where FileManager.default.fileExists(atPath: directory.path) {
			found.append(directory.path)
		}
		let output = artifactsScratch()
		let read = Process()
		read.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
		read.arguments = ["export", preferencesFile.deletingPathExtension().path, output.path]
		read.standardOutput = FileHandle.nullDevice
		read.standardError = FileHandle.nullDevice
		if await Bounded.run(read, timeout: .seconds(10)),
		   let data = try? Data(contentsOf: output),
		   let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		   values.isEmpty == false
		{
			found.append("\(suite) (keys: \(values.keys.sorted().joined(separator: ", ")))")
		}
		try? FileManager.default.removeItem(at: output)
		return found
	}

	/// What the run's settings suite holds now, read through `cfprefsd` as
	/// the application wrote it.
	func storedSettings() async -> [String: Any] {
		let output = artifactsScratch()
		defer { try? FileManager.default.removeItem(at: output) }
		let read = Process()
		read.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
		read.arguments = ["export", preferencesFile.deletingPathExtension().path, output.path]
		read.standardOutput = FileHandle.nullDevice
		read.standardError = FileHandle.nullDevice
		guard await Bounded.run(read, timeout: .seconds(10)),
		      let data = try? Data(contentsOf: output),
		      let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		else { return [:] }
		return values
	}

	private func artifactsScratch() -> URL {
		FileManager.default.temporaryDirectory.appendingPathComponent("glasstual-e2e-\(token).plist")
	}

	/** Removes whatever the application did not. The suite goes through
	 `cfprefsd`, so a cached copy cannot outlive the file. Keychain items are in
	 the application's access group, which only the application can reach; a
	 crashed run's items stay under its unique prefix. */
	func removeLeftovers() async {
		let defaults = Process()
		defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
		defaults.arguments = ["delete", preferencesFile.deletingPathExtension().path]
		defaults.standardOutput = FileHandle.nullDevice
		defaults.standardError = FileHandle.nullDevice
		if FileManager.default.fileExists(atPath: preferencesFile.path) {
			_ = await Bounded.run(defaults, timeout: .seconds(10))
		}
		for item in [groupDirectory, supportDirectory, preferencesFile] {
			try? FileManager.default.removeItem(at: item)
		}
	}
}

/// The settings a scenario's first launch starts from.
enum Seed {
	/// One synthetic network, `E2E`, at `127.0.0.1:port`.
	static func connection(
		corpora: URL,
		port: UInt16,
		secured: Bool = false,
		validatesCertificate: Bool = true
	) throws -> Data {
		var fixture = try startup(corpora: corpora)
		guard var clients = fixture[SettingsKey.serverSessions] as? [[String: Any]], clients.count == 1 else {
			throw HarnessFailure.setup("Malformed synthetic startup fixture")
		}
		clients[0]["uniqueIdentifier"] = UUID().uuidString
		clients[0]["validateServerCertificateChain"] = validatesCertificate
		clients[0]["serverList"] = [[
			"uniqueIdentifier": UUID().uuidString,
			"serverAddress": "127.0.0.1", "serverPort": Int(port), "prefersSecuredConnection": secured,
		]]
		fixture[SettingsKey.serverSessions] = clients
		return try encode(fixture)
	}

	/// No network and onboarding not yet completed.
	static func onboarding(corpora: URL) throws -> Data {
		var fixture = try startup(corpora: corpora)
		fixture[SettingsKey.serverSessions] = [[String: Any]]()
		fixture[SettingsKey.onboardingCompleted] = false
		fixture[SettingsKey.nickname] = ""
		fixture[SettingsKey.realName] = ""
		fixture[SettingsKey.username] = "e2euser"
		return try encode(fixture)
	}

	private static func startup(corpora: URL) throws -> [String: Any] {
		let data = try Data(contentsOf: corpora.appendingPathComponent("E2E/Startup.plist"))
		guard let fixture = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
			throw HarnessFailure.setup("Malformed synthetic startup fixture")
		}
		return fixture
	}

	private static func encode(_ fixture: [String: Any]) throws -> Data {
		try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
	}
}

/// A helper process with a deadline: terminated, then killed, when it overruns.
enum Bounded {
	/// Runs `process` to completion or until `timeout`. Returns whether it
	/// exited by itself with status zero.
	static func run(_ process: Process, timeout: Duration) async -> Bool {
		do {
			try process.run()
		} catch {
			return false
		}
		let finished = await (try? Wait.until("helper exit", timeout: timeout) { process.isRunning == false }) != nil
		if finished == false {
			process.terminate()
			_ = try? await Wait.until("helper terminated", timeout: .seconds(2)) { process.isRunning == false }
			if process.isRunning {
				kill(process.processIdentifier, SIGKILL)
			}
			return false
		}
		return process.terminationReason == .exit && process.terminationStatus == 0
	}
}
