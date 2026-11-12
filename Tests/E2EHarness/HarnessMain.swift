import AppKit
import CryptoKit
import Foundation

/** `glasstual-e2e`: the end-to-end suite, run from a terminal.

     glasstual-e2e run [--only a,b] [--keep-artifacts] [--app <Glasstual.app>]
     glasstual-e2e fixtures [--only a,b]
     glasstual-e2e list

 `run` drives the Debug application through Accessibility and inherits the
 Accessibility grant of the app running the command. `fixtures` checks the
 loopback peers with synthetic clients; it never launches the application or
 uses Accessibility. Exit status: 0 all passed, 1 any failed, 2 setup error. */
@main
enum HarnessMain {
	static func main() async {
		setvbuf(stdout, nil, _IOLBF, 0)
		let arguments = Array(CommandLine.arguments.dropFirst())
		do {
			let options = try Options(arguments)
			switch options.command {
			case "list":
				for scenario in Registry.scenarios {
					print(scenario.name)
				}
				exit(0)
			case "fixtures":
				await exit(FixtureSelfTests.run(corpora: options.corpora, only: options.only) ? 0 : 1)
			case "run":
				try await exit(run(options))
			default:
				throw HarnessFailure.setup("Usage: glasstual-e2e run [--only a,b] [--keep-artifacts] | fixtures | list")
			}
		} catch {
			FileHandle.standardError.write(Data("glasstual-e2e: \(error)\n".utf8))
			exit(2)
		}
	}

	private static func run(_ options: Options) async throws -> Int32 {
		let scenarios = try options.selectedScenarios()
		let app = try AppBundle(url: options.app)
		try Preflight.check()
		let lock = try Preflight.lock()
		defer { close(lock) }
		print(
			"glasstual-e2e: \(scenarios.count) scenarios will drive Glasstual through Accessibility for a few"
				+ " minutes; keep the screen unlocked and leave its windows alone until the summary."
		)
		guard await FixtureSelfTests.run(corpora: options.corpora) else {
			print("glasstual-e2e: loopback fixtures failed; GUI scenarios were not run.")
			return 1
		}
		let runDirectory = options.logs.appendingPathComponent(Self.timestamp(), isDirectory: true)
		let runner = Runner(app: app, corpora: options.corpora, runDirectory: runDirectory,
		                    keepArtifacts: options.keepArtifacts)
		let (results, screenLocked) = await runner.run(scenarios)
		print(Runner.summary(results))
		if (try? FileManager.default.contentsOfDirectory(atPath: runDirectory.path))?.isEmpty == true {
			try? FileManager.default.removeItem(at: runDirectory)
		} else {
			print("Artifacts: \(runDirectory.path)")
		}
		if screenLocked {
			let skipped = scenarios.count - results.count
			print("glasstual-e2e: the screen locked; \(skipped) of \(scenarios.count) scenarios did not run. Unlock it, then rerun.")
			return 2
		}
		return results.allSatisfy { $0.failure == nil } ? 0 : 1
	}

	private static func timestamp() -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
		return formatter.string(from: Date())
	}
}

/// The command line, with defaults taken from where this harness was built.
struct Options {
	let command: String
	let only: Set<String>?
	let keepArtifacts: Bool
	let app: URL
	let checkout: URL

	init(_ arguments: [String]) throws {
		guard let command = arguments.first else {
			throw HarnessFailure.setup("Usage: glasstual-e2e run [--only a,b] [--keep-artifacts] | fixtures | list")
		}
		self.command = command
		var only: Set<String>?
		var keepArtifacts = false
		// The Debug app is built beside the harness, in the same products folder.
		var app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
			.deletingLastPathComponent().appendingPathComponent("Glasstual.app", isDirectory: true)
		var remaining = arguments.dropFirst()
		while let argument = remaining.popFirst() {
			switch argument {
			case "--only":
				guard let list = remaining.popFirst() else { throw HarnessFailure.setup("--only needs a list of names") }
				only = Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
			case "--keep-artifacts":
				keepArtifacts = true
			case "--app":
				guard let path = remaining.popFirst() else { throw HarnessFailure.setup("--app needs a path") }
				app = URL(fileURLWithPath: path, isDirectory: true)
			default:
				throw HarnessFailure.setup("Unknown option \(argument)")
			}
		}
		self.only = only
		self.keepArtifacts = keepArtifacts
		self.app = app
		// The checkout this harness was compiled from: Tests/E2EHarness/HarnessMain.swift.
		checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent()
	}

	var corpora: URL {
		checkout.appendingPathComponent("Tests/Corpora", isDirectory: true)
	}

	/// `~/Library/Logs/Glasstual/<checkout>/e2e`, named the way
	/// `scripts/build-paths.sh` names the checkout's logs.
	var logs: URL {
		let path = checkout.standardizedFileURL.path
		let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
		return FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Logs/Glasstual/\(checkout.lastPathComponent)-\(digest)/e2e", isDirectory: true)
	}

	func selectedScenarios() throws -> [any Scenario] {
		guard let only else { return Registry.scenarios }
		let known = Set(Registry.scenarios.map(\.name))
		let unknown = only.subtracting(known)
		guard unknown.isEmpty else {
			throw HarnessFailure.setup("Unknown scenarios: \(unknown.sorted().joined(separator: ", ")). See glasstual-e2e list.")
		}
		return Registry.scenarios.filter { only.contains($0.name) }
	}
}
