/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
import ImageIO
import os

let mediaAssessorErrorDomain = "ICLMediaAssessorErrorDomain"

private let maximumImageWidth = 7200

private enum MediaAssessorErrorCode: Int {
	case assessmentFailed = 0
	case unexpectedStatusCode = 1001
	case malformedContentType = 1002
	case malformedContentLength = 1003
	case unexpectedType = 1004
	case unexpectedResponse = 1005
	case contentLengthExceeded = 1006
	case maximumWidthExceeded = 1007
	case maximumHeightExceeded = 1008
}

private struct MediaAssessorLimits: Sendable {
	let imageMaximumWidth: Int
	let imageMaximumHeight: Int
	let imageMaximumFilesize: UInt64
}

/// The redirect and authentication policy an assessment is fetched under.
///
/// It holds nothing, which is what lets it be the delegate: `URLSessionDelegate`
/// is declared `NS_SWIFT_SENDABLE`, so a conformer with state would have to
/// claim a `Sendable` conformance it could not honour.
private final class MediaAssessorPolicy: NSObject, URLSessionTaskDelegate, Sendable {
	func urlSession(
		_: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection _: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping @Sendable (URLRequest?) -> Void
	) {
		/* A redirect may keep the scheme or upgrade it, never downgrade it. */
		let originalScheme = task.originalRequest?.url?.scheme?.lowercased()
		let redirectedScheme = request.url?.scheme?.lowercased()
		let allowed = redirectedScheme == "https" || redirectedScheme == "http" && originalScheme == "http"

		completionHandler(allowed ? request : nil)
	}

	func urlSession(
		_: URLSession,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		let method = challenge.protectionSpace.authenticationMethod

		if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
			completionHandler(.cancelAuthenticationChallenge, nil)
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}
}

/// Decides whether a remote URL may be inlined, and as what.
///
/// The whole assessment is one `async` call over `URLSession.bytes`: the headers
/// decide the type, and the body — when one is needed at all — is counted as it
/// arrives and abandoned the moment it passes the file-size cap. There is no
/// delegate holding request state, no cancellation latch and no completion
/// block, so there is nothing here to make `Sendable` by hand.
public enum MediaAssessor {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "MediaAssessor"
	)

	/** SVG is deliberately absent: it is an active content type, and the only
	 thing keeping it inert today is that the template happens to render
	 through `<img src>`. */
	private static let validImageContentTypes: Set<String> = [
		"image/avif", "image/gif", "image/heic", "image/heif", "image/jpeg",
		"image/png", "image/tiff", "image/webp", "image/x-ms-bmp",
	]
	private static let validVideoContentTypes: Set<String> = [
		"video/3gpp", "video/3gpp2", "video/mp4", "video/quicktime", "video/webm", "video/x-m4v",
	]

	private static let policy = MediaAssessorPolicy()

	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		configuration.timeoutIntervalForRequest = InlineContentNetworkLimits.requestTimeout
		configuration.timeoutIntervalForResource = InlineContentNetworkLimits.resourceTimeout
		return URLSession(configuration: configuration)
	}()

	/// Assesses `url`, expecting `expectedType` (`.unknown` accepts anything).
	///
	/// Fails rather than traps: addresses derive from IRC messages and from
	/// remote responses, and this process is shared by every inline load.
	public static func assess(
		_ url: URL,
		expecting expectedType: InlineContentMediaType
	) async -> Result<MediaAssessment, NSError> {
		guard !url.isFileURL else {
			logger.error("Refusing to assess a file URL")

			return .failure(failure("Refusing to assess a file URL", code: .assessmentFailed))
		}

		do {
			return try await .success(fetch(url, expecting: expectedType))
		} catch let assessmentError as NSError where assessmentError.domain == mediaAssessorErrorDomain {
			return .failure(assessmentError)
		} catch {
			return .failure(failure(error.localizedDescription, code: .assessmentFailed))
		}
	}

	/// Assesses an address, which is what the modules have.
	public static func assess(
		address: String,
		expecting expectedType: InlineContentMediaType = .unknown
	) async -> Result<MediaAssessment, NSError> {
		guard let url = URL(string: address) else {
			logger.error("Refusing to assess an unparseable media address")

			return .failure(failure("Refusing to assess an unparseable media address", code: .assessmentFailed))
		}

		return await assess(url, expecting: expectedType)
	}

	public static func logError(_ error: NSError) {
		guard error.domain == mediaAssessorErrorDomain else { return }

		let fatalCodes: Set = [0, 1001, 1002, 1003, 1005]
		let category = fatalCodes.contains(error.code) ? "fatal" : "validation"

		logger.debug("Assessor \(category, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
	}

	// MARK: - Request

	private static func fetch(
		_ url: URL,
		expecting expectedType: InlineContentMediaType
	) async throws -> MediaAssessment {
		let (bytes, response) = try await session.bytes(from: url, delegate: policy)

		guard let response = response as? HTTPURLResponse else {
			bytes.task.cancel()

			throw failure("Invalid response type (not HTTP)", code: .unexpectedResponse)
		}

		let limits = limits(for: expectedType)

		let assessment: MediaAssessment

		do {
			assessment = try readHeaders(from: response, url: url, expecting: expectedType)
		} catch {
			bytes.task.cancel()

			throw error
		}

		guard shouldReadBody(for: assessment, response: response, limits: limits) else {
			/* Cancelling the task is what stops the transfer; nothing in the
			 body is wanted. */
			bytes.task.cancel()

			return assessment
		}

		let body = try await read(bytes, upTo: limits?.imageMaximumFilesize ?? 0)

		try validate(body, against: limits, for: assessment)

		return assessment
	}

	private static func limits(for expectedType: InlineContentMediaType) -> MediaAssessorLimits? {
		guard expectedType == .unknown || expectedType == .image else { return nil }

		return MediaAssessorLimits(
			imageMaximumWidth: maximumImageWidth,
			imageMaximumHeight: Int(InlineContentPreferences.current.maximumHeight),
			imageMaximumFilesize: InlineContentPreferences.current.maximumImageFileSize
		)
	}

	private static func readHeaders(
		from response: HTTPURLResponse,
		url: URL,
		expecting expectedType: InlineContentMediaType
	) throws -> MediaAssessment {
		guard response.statusCode == 200 else {
			throw failure("Endpoint did not respond with OK (200)", code: .unexpectedStatusCode)
		}

		let contentType = response.mimeType ?? "application/binary"

		guard contentType.count <= 128 else {
			throw failure("Content-Type header is improperly formatted", code: .malformedContentType)
		}

		let responseLength = response.expectedContentLength

		guard responseLength == NSURLSessionTransferSizeUnknown || responseLength >= 0 else {
			throw failure("Content-Length header is improperly formatted", code: .malformedContentLength)
		}

		let mediaType: InlineContentMediaType = if validImageContentTypes.contains(contentType) {
			.image
		} else if validVideoContentTypes.contains(contentType) {
			.video
		} else {
			.other
		}

		if expectedType != .unknown, expectedType != mediaType {
			throw failure("Unexpected media type", code: .unexpectedType)
		}

		let contentLength = responseLength == NSURLSessionTransferSizeUnknown ? UInt64(0) : UInt64(responseLength)

		if mediaType == .image,
		   responseLength != NSURLSessionTransferSizeUnknown,
		   let maximum = limits(for: expectedType)?.imageMaximumFilesize,
		   maximum > 0,
		   contentLength > maximum
		{
			throw failure("Content-Length exceeds maximum allowed", code: .contentLengthExceeded)
		}

		return MediaAssessment(
			url: response.url ?? url,
			type: mediaType,
			contentType: contentType,
			contentLength: contentLength
		)
	}

	/// Whether the body has to be read at all: to measure the image, or to
	/// count bytes the server declined to declare.
	private static func shouldReadBody(
		for assessment: MediaAssessment,
		response: HTTPURLResponse,
		limits: MediaAssessorLimits?
	) -> Bool {
		guard assessment.type == .image, let limits else { return false }

		if response.expectedContentLength == NSURLSessionTransferSizeUnknown {
			/* Without a Content-Length the only way to hold the server to the
			 file-size cap is to read the body and count. */
			return limits.imageMaximumFilesize > 0 || limits.imageMaximumHeight > 0
		}

		/* The height cap is optional; the width cap is not, and neither can be
		 applied without the pixels. */
		return limits.imageMaximumHeight > 0 || limits.imageMaximumWidth > 0
	}

	/// Reads the body, counting as it goes, and gives up the moment it passes
	/// `maximum`. A cap of zero means the user asked for none.
	private static func read(_ bytes: URLSession.AsyncBytes, upTo maximum: UInt64) async throws -> Data {
		var body = Data()

		do {
			for try await byte in bytes {
				body.append(byte)

				if maximum > 0, UInt64(body.count) > maximum {
					bytes.task.cancel()

					throw failure("Maximum response size exceeded", code: .contentLengthExceeded)
				}
			}
		} catch {
			bytes.task.cancel()

			throw error
		}

		return body
	}

	private static func validate(
		_ body: Data,
		against limits: MediaAssessorLimits?,
		for assessment: MediaAssessment
	) throws {
		guard assessment.type == .image, let limits else { return }

		guard let imageSource = CGImageSourceCreateWithData(body as CFData, nil) else {
			throw failure("Image validation: CGImageSourceCreateWithData() returned NULL", code: .assessmentFailed)
		}

		guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
			throw failure(
				"Image validation: CGImageSourceCopyPropertiesAtIndex() returned NULL",
				code: .assessmentFailed
			)
		}

		let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
		let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

		if width > limits.imageMaximumWidth {
			throw failure("Image validation: Maximum width exceeded", code: .maximumWidthExceeded)
		}

		/* A height cap of zero means the user did not ask for one. */
		if limits.imageMaximumHeight > 0, height > limits.imageMaximumHeight {
			throw failure("Image validation: Maximum height exceeded", code: .maximumHeightExceeded)
		}
	}

	private static func failure(_ description: String, code: MediaAssessorErrorCode) -> NSError {
		NSError(
			domain: mediaAssessorErrorDomain,
			code: code.rawValue,
			userInfo: [NSLocalizedDescriptionKey: description]
		)
	}
}
