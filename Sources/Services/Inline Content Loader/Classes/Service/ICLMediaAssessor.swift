/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

private let mediaAssessorErrorDomain = "ICLMediaAssessorErrorDomain"
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

private struct MediaAssessorConfiguration: @unchecked Sendable {
	let completion: (MediaAssessment?, NSError?) -> Void
	let expectedType: ICLMediaType
	let url: URL
}

private struct MediaAssessorLimits: Sendable {
	let imageMaximumWidth: Int
	let imageMaximumHeight: Int
	let imageMaximumFilesize: UInt64
}

private final class MediaAssessorRequest: @unchecked Sendable {
	var session: URLSession?
	var task: URLSessionTask?
	var alternateError: NSError?
	var doNotFinalize = false
}

private struct MediaAssessorState: @unchecked Sendable {
	let assessment: MediaAssessment
	let performExtendedValidation: Bool
}

@objc(ICLMediaAssessor)
final class MediaAssessor: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "MediaAssessor"
	)
	private static let validImageContentTypes: Set<String> = [
		"image/gif", "image/jpeg", "image/png", "image/svg+xml", "image/tiff", "image/x-ms-bmp",
	]
	private static let validVideoContentTypes: Set<String> = [
		"video/3gpp", "video/3gpp2", "video/mp4", "video/quicktime", "video/x-m4v",
	]

	private var configuration: MediaAssessorConfiguration?
	private var limits: MediaAssessorLimits?
	private var request: MediaAssessorRequest?
	private var state: MediaAssessorState?

	@available(*, unavailable, message: "Use a factory method")
	override init() {
		fatalError("Use a factory method")
	}

	init(
		url: URL,
		expectedType: ICLMediaType,
		completion: @escaping (MediaAssessment?, NSError?) -> Void
	) {
		precondition(!url.isFileURL)
		configuration = MediaAssessorConfiguration(
			completion: completion,
			expectedType: expectedType,
			url: url
		)
		super.init()
	}

	@objc(assessorForURL:completionBlock:)
	class func assessor(
		for url: URL,
		completionBlock: @escaping (MediaAssessment?, NSError?) -> Void
	) -> MediaAssessor {
		MediaAssessor(url: url, expectedType: .unknown, completion: completionBlock)
	}

	@objc(assessorForAddress:completionBlock:)
	class func assessor(
		forAddress address: String,
		completionBlock: @escaping (MediaAssessment?, NSError?) -> Void
	) -> MediaAssessor {
		assessor(forAddress: address, with: .unknown, completionBlock: completionBlock)
	}

	@objc(assessorForURL:withType:completionBlock:)
	class func assessor(
		for url: URL,
		with type: ICLMediaType,
		completionBlock: @escaping (MediaAssessment?, NSError?) -> Void
	) -> MediaAssessor {
		MediaAssessor(url: url, expectedType: type, completion: completionBlock)
	}

	@objc(assessorForAddress:withType:completionBlock:)
	class func assessor(
		forAddress address: String,
		with type: ICLMediaType,
		completionBlock: @escaping (MediaAssessment?, NSError?) -> Void
	) -> MediaAssessor {
		guard let url = URL(string: address) else {
			preconditionFailure("Invalid media address")
		}
		return MediaAssessor(url: url, expectedType: type, completion: completionBlock)
	}

	@objc
	func resume() {
		precondition(request == nil, "An assessment is already in progress")
		guard let configuration else {
			preconditionFailure("resume() called after the assessment finalized")
		}

		let delegateQueue = OperationQueue()
		delegateQueue.name = "com.vakesz.glasstual.media-assessor"
		delegateQueue.maxConcurrentOperationCount = 1

		let sessionConfiguration = URLSessionConfiguration.ephemeral
		sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
		sessionConfiguration.httpShouldSetCookies = false
		sessionConfiguration.httpCookieAcceptPolicy = .never

		let request = MediaAssessorRequest()
		let session = URLSession(
			configuration: sessionConfiguration,
			delegate: self,
			delegateQueue: delegateQueue
		)
		let task = session.dataTask(with: configuration.url)
		request.session = session
		request.task = task
		self.request = request

		if configuration.expectedType == .unknown || configuration.expectedType == .image {
			limits = MediaAssessorLimits(
				imageMaximumWidth: maximumImageWidth,
				imageMaximumHeight: Int(TPCPreferences.inlineMediaMaxHeight()),
				imageMaximumFilesize: TPCPreferences.inlineImagesMaxFilesize()
			)
		}

		task.resume()
	}

	@objc
	func suspend() {
		guard let request else { return }
		request.doNotFinalize = true
		request.session?.invalidateAndCancel()
	}

	private func finish(with error: Error?) {
		var finalError = error as NSError?
		if finalError?.domain == NSURLErrorDomain, finalError?.code == NSURLErrorCancelled {
			finalError = request?.alternateError
		}

		if finalError == nil, state?.assessment == nil {
			finalError = makeError("Assessment failed", code: .assessmentFailed)
		}

		configuration?.completion(state?.assessment, finalError)
		flushRequestState()
		configuration = nil
	}

	private func flushRequestState() {
		limits = nil
		state = nil
		request = nil
	}

	private func makeError(_ description: String, code: MediaAssessorErrorCode) -> NSError {
		NSError(
			domain: mediaAssessorErrorDomain,
			code: code.rawValue,
			userInfo: [NSLocalizedDescriptionKey: description]
		)
	}

	private func readHeaders(from response: HTTPURLResponse) throws -> MediaAssessorState {
		guard response.statusCode == 200 else {
			throw makeError("Endpoint did not respond with OK (200)", code: .unexpectedStatusCode)
		}

		let contentType = response.mimeType ?? "application/binary"
		guard contentType.count <= 128 else {
			throw makeError("Content-Type header is improperly formatted", code: .malformedContentType)
		}

		let responseLength = response.expectedContentLength
		guard responseLength == NSURLSessionTransferSizeUnknown || responseLength >= 0 else {
			throw makeError("Content-Length header is improperly formatted", code: .malformedContentLength)
		}
		let contentLength = responseLength == NSURLSessionTransferSizeUnknown ? UInt64(0) : UInt64(responseLength)

		let mediaType: ICLMediaType = if Self.validImageContentTypes.contains(contentType) {
			.image
		} else if Self.validVideoContentTypes.contains(contentType) {
			.video
		} else {
			.other
		}

		if let expectedType = configuration?.expectedType,
		   expectedType != .unknown,
		   expectedType != mediaType
		{
			throw makeError("Unexpected media type", code: .unexpectedType)
		}

		var performExtendedValidation = false
		if mediaType == .image, let limits {
			guard contentLength <= limits.imageMaximumFilesize else {
				throw makeError("Content-Length exceeds maximum allowed", code: .contentLengthExceeded)
			}
			performExtendedValidation = limits.imageMaximumHeight > 0
		}

		let assessment = MediaAssessmentMutable(
			url: response.url ?? configuration?.url ?? URL(string: "about:blank")!,
			type: mediaType
		)
		assessment.contentType = contentType
		assessment.contentLength = contentLength
		return MediaAssessorState(
			assessment: assessment,
			performExtendedValidation: performExtendedValidation
		)
	}

	func urlSession(
		_: URLSession,
		dataTask _: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
	) {
		guard let response = response as? HTTPURLResponse else {
			request?.alternateError = makeError("Invalid response type (not HTTP)", code: .unexpectedResponse)
			return completionHandler(.cancel)
		}

		do {
			let state = try readHeaders(from: response)
			self.state = state
			completionHandler(state.performExtendedValidation ? .becomeDownload : .cancel)
		} catch {
			request?.alternateError = error as NSError
			completionHandler(.cancel)
		}
	}

	func urlSession(
		_: URLSession,
		dataTask _: URLSessionDataTask,
		willCacheResponse _: CachedURLResponse,
		completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void
	) {
		completionHandler(nil)
	}

	func urlSession(
		_: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection _: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping @Sendable (URLRequest?) -> Void
	) {
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

	func urlSession(
		_: URLSession,
		dataTask _: URLSessionDataTask,
		didBecome downloadTask: URLSessionDownloadTask
	) {
		request?.task = downloadTask
	}

	func urlSession(
		_ session: URLSession,
		downloadTask _: URLSessionDownloadTask,
		didFinishDownloadingTo location: URL
	) {
		do {
			try performExtendedValidation(at: location)
		} catch {
			request?.alternateError = error as NSError
			session.invalidateAndCancel()
		}
	}

	func urlSession(
		_ session: URLSession,
		downloadTask _: URLSessionDownloadTask,
		didWriteData _: Int64,
		totalBytesWritten: Int64,
		totalBytesExpectedToWrite _: Int64
	) {
		guard downloadExceededMaximumFileSize(UInt64(max(0, totalBytesWritten))) else { return }
		request?.alternateError = makeError("Maximum response size exceeded", code: .contentLengthExceeded)
		session.invalidateAndCancel()
	}

	func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
		let shouldFinalize = request?.doNotFinalize != true
		if shouldFinalize {
			finish(with: error)
		} else {
			flushRequestState()
		}
		session.finishTasksAndInvalidate()
	}

	func urlSession(_ session: URLSession, didBecomeInvalidWithError _: Error?) {
		if request?.session === session {
			request?.session = nil
		}
	}

	private func downloadExceededMaximumFileSize(_ progress: UInt64) -> Bool {
		guard state?.assessment.type == .image, let maximum = limits?.imageMaximumFilesize, maximum > 0 else {
			return false
		}
		return progress > maximum
	}

	private func performExtendedValidation(at url: URL) throws {
		guard state?.assessment.type == .image else { return }
		guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			throw makeError(
				"Image validation: CGImageSourceCreateWithURL() returned NULL",
				code: .assessmentFailed
			)
		}
		guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
			throw makeError(
				"Image validation: CGImageSourceCopyPropertiesAtIndex() returned NULL",
				code: .assessmentFailed
			)
		}

		let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
		let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
		guard let limits else { return }

		if width > limits.imageMaximumWidth {
			throw makeError("Image validation: Maximum width exceeded", code: .maximumWidthExceeded)
		}
		if height > limits.imageMaximumHeight {
			throw makeError("Image validation: Maximum height exceeded", code: .maximumHeightExceeded)
		}
	}

	@objc(logError:)
	class func logError(_ error: NSError) {
		guard error.domain == mediaAssessorErrorDomain else { return }
		let fatalCodes: Set = [0, 1001, 1002, 1003, 1005]
		let category = fatalCodes.contains(error.code) ? "fatal" : "validation"
		logger.debug("Assessor \(category, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
	}
}
