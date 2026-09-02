/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import ImageIO

nonisolated enum NativeInlineImageError: LocalizedError, Sendable { // nonisolated: value
	case invalidResponse
	case unsupportedContent
	case bodyTooLarge

	var errorDescription: String? {
		switch self {
		case .invalidResponse: "The server returned an invalid response."
		case .unsupportedContent: "The address does not contain a supported image."
		case .bodyTooLarge: "The image exceeds the 16 MB download limit."
		}
	}
}

/// Downloads the native transcript's inline images. The view owns decoding and
/// display; this type owns the network boundary and its size and MIME checks.
@MainActor
final class NativeInlineImageLoader {
	static let shared = NativeInlineImageLoader()

	private nonisolated static let maximumByteCount = 16 * 1024 * 1024 // nonisolated: let
	/// How much of a body is collected before it is handed to the accumulator.
	/// The bytes arrive one at a time; appending them to `Data` one at a time is
	/// what makes a large image expensive.
	private nonisolated static let chunkByteCount = 64 * 1024 // nonisolated: let
	/// The downloads in flight, per transcript view, so closing a view takes its
	/// requests with it.
	private var tasks: [String: [String: Task<Void, Never>]] = [:]

	private init() {}

	func load(
		url: URL,
		viewIdentifier: String,
		lineNumber: String,
		linkIdentifier: String,
		completion: @escaping @MainActor (Result<TranscriptInlineImage, Error>) -> Void
	) {
		let key = "\(lineNumber):\(linkIdentifier)"
		guard tasks[viewIdentifier]?[key] == nil else { return }
		tasks[viewIdentifier, default: [:]][key] = Task { [weak self] in
			defer { self?.tasks[viewIdentifier]?.removeValue(forKey: key) }
			do {
				let data = try await Self.download(url)
				completion(.success(TranscriptInlineImage(
					lineNumber: lineNumber,
					linkIdentifier: linkIdentifier,
					sourceURL: url,
					imageData: data
				)))
			} catch is CancellationError {
				return
			} catch {
				completion(.failure(error))
			}
		}
	}

	/// Drops the downloads a view is still waiting for. Its transcript is going
	/// away, so nothing is left to draw them on.
	func cancelLoads(forView viewIdentifier: String) {
		guard let cancelled = tasks.removeValue(forKey: viewIdentifier) else { return }
		for task in cancelled.values {
			task.cancel()
		}
	}

	/** Fetches and validates one image body.

	 `@concurrent` rather than the project's `nonisolated(nonsending)` default: a
	 plain `nonisolated async` function runs on its caller's executor, and the
	 caller here is a main-actor task — which would put the whole transfer, the
	 body accumulation and the image probe on the main thread. */
	@concurrent
	private nonisolated static func download(_ url: URL) async throws -> Data { // nonisolated: pure
		guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			throw NativeInlineImageError.unsupportedContent
		}
		var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
		request.setValue("image/*", forHTTPHeaderField: "Accept")
		let (bytes, response) = try await URLSession.shared.bytes(for: request)
		guard let response = response as? HTTPURLResponse,
		      (200 ..< 300).contains(response.statusCode)
		else {
			throw NativeInlineImageError.invalidResponse
		}
		guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
			throw NativeInlineImageError.unsupportedContent
		}
		guard response.expectedContentLength <= Int64(maximumByteCount) else {
			throw NativeInlineImageError.bodyTooLarge
		}
		var data = Data()
		if response.expectedContentLength > 0 {
			data.reserveCapacity(Int(response.expectedContentLength))
		}
		/* `AsyncBytes` yields one byte at a time and has no chunked accessor, so
		 the run is buffered here and handed over in blocks: the cap is still
		 checked before anything is kept, and `Data` grows once per block rather
		 than once per byte. */
		var chunk: [UInt8] = []
		chunk.reserveCapacity(chunkByteCount)
		for try await byte in bytes {
			guard data.count + chunk.count < maximumByteCount else {
				throw NativeInlineImageError.bodyTooLarge
			}
			chunk.append(byte)
			if chunk.count == chunkByteCount {
				data.append(contentsOf: chunk)
				chunk.removeAll(keepingCapacity: true)
			}
		}
		data.append(contentsOf: chunk)
		guard data.isEmpty == false,
		      CGImageSourceCreateWithData(data as CFData, nil) != nil
		else {
			throw NativeInlineImageError.unsupportedContent
		}
		return data
	}
}
