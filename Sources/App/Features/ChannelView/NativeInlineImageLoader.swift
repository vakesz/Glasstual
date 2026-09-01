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
	private var tasks: [String: Task<Void, Never>] = [:]

	private init() {}

	func load(
		url: URL,
		lineNumber: String,
		linkIdentifier: String,
		completion: @escaping @MainActor (Result<TranscriptInlineImage, Error>) -> Void
	) {
		let key = "\(lineNumber):\(linkIdentifier)"
		guard tasks[key] == nil else { return }
		tasks[key] = Task { [weak self] in
			defer { self?.tasks.removeValue(forKey: key) }
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
		for try await byte in bytes {
			guard data.count < maximumByteCount else { throw NativeInlineImageError.bodyTooLarge }
			data.append(byte)
		}
		guard data.isEmpty == false,
		      CGImageSourceCreateWithData(data as CFData, nil) != nil
		else {
			throw NativeInlineImageError.unsupportedContent
		}
		return data
	}
}
