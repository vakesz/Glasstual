import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/** Pictures of the application's windows, taken with `screencapture` by window
 number: the window alone, without its shadow, whatever else is on screen and
 whichever application is in front. Needs the Screen Recording grant. */
enum WindowCapture {
	static func requireAccess() throws {
		guard CGPreflightScreenCaptureAccess() else {
			throw HarnessFailure.setup(
				"Grant Screen Recording to the app running this command in System Settings > Privacy & Security >"
					+ " Screen & System Audio Recording, then rerun."
			)
		}
	}

	/// The window-server number of `pid`'s on-screen window at `frame`, which
	/// is the frame Accessibility reports: screen points, top-left origin.
	static func windowNumber(pid: pid_t, frame: CGRect) -> CGWindowID? {
		let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
			as? [[String: Any]] ?? []
		for window in windows {
			guard (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
			      window[kCGWindowLayer as String] as? Int == 0,
			      let number = window[kCGWindowNumber as String] as? Int,
			      let bounds = window[kCGWindowBounds as String] as? NSDictionary,
			      let rect = CGRect(dictionaryRepresentation: bounds),
			      abs(rect.minX - frame.minX) <= 2, abs(rect.minY - frame.minY) <= 2,
			      abs(rect.width - frame.width) <= 2, abs(rect.height - frame.height) <= 2
			else { continue }
			return CGWindowID(number)
		}
		return nil
	}

	/// Captures window `number` and returns the picture, or `nil` when
	/// `screencapture` did not produce one.
	static func capture(_ number: CGWindowID, scratch: URL) async -> CGImage? {
		try? FileManager.default.removeItem(at: scratch)
		let capture = Process()
		capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
		capture.arguments = ["-x", "-o", "-l", String(number), scratch.path]
		capture.standardOutput = FileHandle.nullDevice
		capture.standardError = FileHandle.nullDevice
		guard await Bounded.run(capture, timeout: .seconds(10)),
		      let source = CGImageSourceCreateWithURL(scratch as CFURL, nil)
		else { return nil }
		return CGImageSourceCreateImageAtIndex(source, 0, nil)
	}

	/// A digest of the picture's pixels, to tell whether two captures differ.
	static func digest(_ image: CGImage) -> String {
		guard let data = image.dataProvider?.data as Data? else { return UUID().uuidString }
		return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}

	/** `image` drawn into `size` pixels in sRGB, cropped to `crop` of the
	 scaled picture when given. A capture is as many pixels as the display's
	 scale makes it; the published file is one pixel per point, whatever
	 display the run happened on. */
	static func render(_ image: CGImage, size: CGSize, cropTop: CGFloat = 0, scaledHeight: CGFloat? = nil) throws -> CGImage {
		guard let space = CGColorSpace(name: CGColorSpace.sRGB),
		      let context = CGContext(
		      	data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
		      	space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		      )
		else { throw HarnessFailure.setup("Cannot create a bitmap of \(Int(size.width)) x \(Int(size.height))") }
		context.interpolationQuality = .high
		let height = scaledHeight ?? size.height
		// Core Graphics draws from the bottom left; `cropTop` is cut off the top.
		context.draw(image, in: CGRect(x: 0, y: size.height - height + cropTop, width: size.width, height: height))
		guard let result = context.makeImage() else { throw HarnessFailure.setup("Cannot render the picture") }
		return result
	}

	/// Writes `image` as a PNG without metadata, then lets `pngquant` shrink
	/// it when that is installed.
	static func write(_ image: CGImage, to file: URL) async throws {
		guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)
		else { throw HarnessFailure.setup("Cannot write \(file.path)") }
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else { throw HarnessFailure.setup("Cannot write \(file.path)") }
		guard let pngquant else { return }
		let shrink = Process()
		shrink.executableURL = pngquant
		shrink.arguments = ["--force", "--strip", "--skip-if-larger", "--quality", "85-100", "--output", file.path, file.path]
		shrink.standardOutput = FileHandle.nullDevice
		shrink.standardError = FileHandle.nullDevice
		// Exit 98 and 99 mean the file is better left as it is.
		_ = await Bounded.run(shrink, timeout: .seconds(30))
	}

	private static let pngquant: URL? = ["/opt/homebrew/bin/pngquant", "/usr/local/bin/pngquant"]
		.first { FileManager.default.isExecutableFile(atPath: $0) }
		.map { URL(fileURLWithPath: $0) }

	/// The application's icon as the Finder draws it, `side` pixels square.
	static func icon(of app: AppBundle, side: Int) throws -> CGImage {
		let icon = NSWorkspace.shared.icon(forFile: app.url.path)
		var rect = CGRect(x: 0, y: 0, width: side, height: side)
		guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
			throw HarnessFailure.setup("Cannot draw the application icon")
		}
		return try render(image, size: CGSize(width: side, height: side))
	}
}
