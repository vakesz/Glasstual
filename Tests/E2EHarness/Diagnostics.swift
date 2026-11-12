import AppKit
import CoreGraphics
import Foundation

/** What a failed scenario leaves for whoever has to work out why.

 Everything is bounded in size and time, and none of it can fail the run: the
 failure being described has already happened. App standard output and error
 are already in the scenario's directory, written there as the scenario ran. */
enum Diagnostics {
	/// Collects the AX tree, a window screenshot, the unified log and a
	/// main-thread sample for each launch still running, and the log for every
	/// launch, into `directory`.
	static func collect(for launches: [AppProcess], app: AppBundle, notes: [String], into directory: URL) async {
		write(notes.joined(separator: "\n") + "\n", to: directory.appendingPathComponent("notes.txt"))
		for (index, launch) in launches.enumerated() {
			let label = "app-\(index + 1)"
			if launch.isRunning {
				write(launch.driver.dump(), to: directory.appendingPathComponent("\(label)-ax-tree.txt"))
				await screenshot(of: launch.pid, to: directory.appendingPathComponent("\(label)-window.png"))
				await sample(launch.pid, to: directory.appendingPathComponent("\(label)-main-thread.txt"))
			} else {
				write("Exited: \(launch.exitDescription)\n", to: directory.appendingPathComponent("\(label)-exit.txt"))
			}
			await log(of: launch, app: app, to: directory.appendingPathComponent("\(label)-log.txt"))
		}
	}

	/// The application's frontmost on-screen window, captured only when the
	/// login has granted Screen Recording; never asks for it.
	private static func screenshot(of pid: pid_t, to file: URL) async {
		guard CGPreflightScreenCaptureAccess() else { return }
		let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
			as? [[String: Any]] ?? []
		guard let window = windows.first(where: {
			($0[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid
				&& ($0[kCGWindowLayer as String] as? Int) == 0
		}), let number = window[kCGWindowNumber as String] as? Int else { return }
		let capture = Process()
		capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
		capture.arguments = ["-x", "-o", "-l", String(number), file.path]
		capture.standardOutput = FileHandle.nullDevice
		capture.standardError = FileHandle.nullDevice
		_ = await Bounded.run(capture, timeout: .seconds(10))
	}

	/// The unified log since launch for the application's pid and for every
	/// process inside its bundle, which is how the XPC connection host is found.
	private static func log(of launch: AppProcess, app: AppBundle, to file: URL) async {
		let start = Date(timeInterval: -1, since: launch.launchedAt)
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		let bundlePath = app.url.path.replacingOccurrences(of: "\"", with: "")
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
		process.arguments = [
			"show", "--style", "compact", "--info", "--debug", "--start", formatter.string(from: start),
			"--predicate", "processID == \(launch.pid) OR processImagePath BEGINSWITH \"\(bundlePath)\"",
		]
		guard FileManager.default.createFile(atPath: file.path, contents: nil),
		      let handle = try? FileHandle(forWritingTo: file)
		else { return }
		defer { try? handle.close() }
		process.standardOutput = handle
		process.standardError = handle
		_ = await Bounded.run(process, timeout: .seconds(45))
	}

	/// A one-second sample of the main thread, reduced to symbols from a fixed
	/// set of modules: no paths, addresses or strings.
	private static func sample(_ pid: pid_t, to file: URL) async {
		let raw = file.deletingPathExtension().appendingPathExtension("raw")
		defer { try? FileManager.default.removeItem(at: raw) }
		let sampler = Process()
		sampler.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
		sampler.arguments = [String(pid), "1", "10", "-file", raw.path]
		sampler.standardOutput = FileHandle.nullDevice
		sampler.standardError = FileHandle.nullDevice
		_ = await Bounded.run(sampler, timeout: .seconds(10))
		let captured = (try? Data(contentsOf: raw)) ?? Data()
		write(mainThreadSummary(captured.prefix(131_072)), to: file)
	}

	static func mainThreadSummary(_ data: Data) -> String {
		let text = String(data: data, encoding: .utf8) ?? ""
		let modules = ["Glasstual", "AppKit", "CoreFoundation", "Foundation", "libswift_Concurrency.dylib",
		               "libdispatch.dylib", "libsystem_kernel.dylib", "libsystem_pthread.dylib"]
		var mainThread = false
		var frames: [String] = []
		for line in text.split(separator: "\n") {
			if line.contains("Thread_") {
				mainThread = line.contains("com.apple.main-thread")
			}
			guard mainThread, frames.count < 80 else { continue }
			for module in modules {
				guard let end = line.range(of: " (in \(module))")?.lowerBound else { continue }
				let symbol = line[..<end].trimmingCharacters(in: CharacterSet(charactersIn: " +-!:|0123456789\t"))
				// Keep static symbols only, not paths, quoted strings, addresses, headers or binary images.
				guard !symbol.isEmpty, symbol.utf8.count <= 512, !symbol.contains("0x"),
				      symbol.utf8.allSatisfy({ (32 ... 126).contains($0) && ![34, 39, 47, 92].contains($0) })
				else { continue }
				frames.append("\(module): \(symbol)")
			}
		}
		return "Bounded main-thread sample; allowed modules only.\n" +
			(frames.isEmpty ? "No permitted main-thread frames available." : frames.joined(separator: "\n")) + "\n"
	}

	private static func write(_ text: String, to file: URL) {
		try? Data(text.utf8).write(to: file, options: .atomic)
	}
}
