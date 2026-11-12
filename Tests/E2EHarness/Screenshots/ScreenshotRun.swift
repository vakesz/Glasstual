import AppKit
import Foundation

/** `glasstual-e2e screenshots`: the website's pictures, from a seeded demo.

 Each scene group is one launch of the application in one appearance, run by
 ``Runner`` like any end-to-end scenario: its own sandbox, loopback servers
 that script a fictional conversation, controls found by identifier and waits
 on conditions. The pictures go to `.github/website/assets` under the names
 the pages already use, one pixel per point. The application icon is drawn
 again at the two sizes the pages use, so those files follow the icon. */
enum ScreenshotRun {
	/// The icon sizes the website uses, by file name.
	private static let icons = ["app-icon-64.png": 64, "app-icon-192.png": 192]
	/// What the link preview is cut from, and its size.
	private static let previewSource = "main-window-light.png"
	private static let previewSize = CGSize(width: 1200, height: 630)

	static func scenarios(_ options: Options) throws -> [ScreenshotScenario] {
		let groups = try options.only.map { names in
			try names.sorted().map { name -> ScreenshotScenario.Group in
				guard let group = ScreenshotScenario.Group(rawValue: name) else {
					let known = ScreenshotScenario.Group.allCases.map(\.rawValue).joined(separator: ", ")
					throw HarnessFailure.setup("Unknown scene group \(name). Groups: \(known).")
				}
				return group
			}
		} ?? ScreenshotScenario.Group.allCases
		return ScreenshotAppearance.allCases.flatMap { appearance in
			groups.map { ScreenshotScenario(group: $0, appearance: appearance, output: options.output) }
		}
	}

	/// Runs the scenes, then derives the link preview and the icons. Returns
	/// the process's exit status.
	static func run(_ options: Options, runDirectory: URL) async throws -> Int32 {
		let scenarios = try scenarios(options)
		let app = try AppBundle(url: options.app)
		try Preflight.check()
		try WindowCapture.requireAccess()
		let lock = try Preflight.lock()
		defer { close(lock) }
		try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
		print(
			"glasstual-e2e: \(scenarios.count) screenshot scenes will drive Glasstual and bring its windows forward"
				+ " for a few minutes; keep the screen unlocked and leave its windows alone until the summary."
		)
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
			print("glasstual-e2e: the screen locked; \(scenarios.count - results.count) scenes did not run. Unlock it, then rerun.")
			return 2
		}
		try await derive(from: app, into: options.output)
		print("Screenshots: \(options.output.path)")
		return results.allSatisfy { $0.failure == nil } ? 0 : 1
	}

	/// The link preview, cut from the middle of the light main window, and
	/// the application icon at the sizes the pages use.
	private static func derive(from app: AppBundle, into output: URL) async throws {
		let source = output.appendingPathComponent(previewSource)
		if let image = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
			let scaledHeight = (previewSize.width * CGFloat(image.height) / CGFloat(image.width)).rounded()
			let preview = try WindowCapture.render(
				image, size: previewSize, cropTop: ((scaledHeight - previewSize.height) / 2).rounded(),
				scaledHeight: scaledHeight
			)
			try await WindowCapture.write(preview, to: output.appendingPathComponent("og.png"))
			print("  og.png  \(Int(previewSize.width)) x \(Int(previewSize.height))")
		}
		for (name, side) in icons.sorted(by: { $0.value < $1.value }) {
			try await WindowCapture.write(WindowCapture.icon(of: app, side: side), to: output.appendingPathComponent(name))
			print("  \(name)  \(side) x \(side)")
		}
	}
}
