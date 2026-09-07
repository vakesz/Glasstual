import Foundation

enum ProcessDiagnostics {
	static func summary(_ data: Data) -> String {
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
			(frames.isEmpty ? "No permitted main-thread frames available." : frames.joined(separator: "\n"))
	}
}
