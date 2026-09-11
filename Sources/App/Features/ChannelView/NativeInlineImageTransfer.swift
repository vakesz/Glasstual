/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Synchronization

/// URLSession invokes the delegate outside actor isolation. Its only mutable
/// storage is a bounded value; no task or unbounded stream is created per chunk.
final nonisolated class NativeInlineImageTransfer: NSObject, Sendable { // nonisolated: immutable
	private struct State {
		var data = Data()
		var failure: NativeInlineImageError?
		var continuation: CheckedContinuation<Data, any Error>?
		var redirects = 0
		/// Set once the surrounding task was cancelled and the session torn
		/// down, so a continuation installed afterwards is not left waiting on
		/// a data task that will never run.
		var isCancelled = false
	}

	private let state = Mutex(State())
	private let maximumBytes: Int

	private init(maximumBytes: Int) {
		self.maximumBytes = maximumBytes
	}

	static func isHTTP(_ url: URL) -> Bool {
		["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
	}

	@concurrent
	static func download(_ url: URL, limits: NativeInlineImageLimits,
	                     protocolClasses: [URLProtocol.Type]) async throws -> Data
	{
		try Task.checkCancellation()
		guard isHTTP(url) else { throw NativeInlineImageError.unsupportedContent }
		guard limits.workingByteCount != nil else { throw NativeInlineImageError.resourceLimit }
		let configuration = URLSessionConfiguration.ephemeral
		configuration.urlCache = nil
		configuration.httpCookieStorage = nil
		configuration.urlCredentialStorage = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.timeoutIntervalForRequest = 30
		configuration.timeoutIntervalForResource = 60
		if !protocolClasses.isEmpty {
			configuration.protocolClasses = protocolClasses
		}
		let delegate = NativeInlineImageTransfer(maximumBytes: limits.maximumEncodedBytes)
		let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
		defer { session.invalidateAndCancel() }
		return try await withTaskCancellationHandler {
			try Task.checkCancellation()
			return try await withCheckedThrowingContinuation { continuation in
				/* Cancellation can arrive between the check above and this
				 line. It would then invalidate the session before the data
				 task was ever resumed, and nothing would come back to resume
				 the continuation, so the cancelled state is re-read here under
				 the same lock that installs it. */
				let cancelled = delegate.state.withLock { state -> Bool in
					guard state.isCancelled == false else { return true }
					state.continuation = continuation
					return false
				}
				guard cancelled == false else {
					continuation.resume(throwing: CancellationError())
					return
				}
				var request = URLRequest(url: url)
				request.setValue("image/*", forHTTPHeaderField: "Accept")
				session.dataTask(with: request).resume()
			}
		} onCancel: {
			let continuation = delegate.state.withLock { state -> CheckedContinuation<Data, any Error>? in
				state.isCancelled = true
				defer { state.continuation = nil }
				return state.continuation
			}
			session.invalidateAndCancel()
			continuation?.resume(throwing: CancellationError())
		}
	}
}

nonisolated extension NativeInlineImageTransfer: URLSessionDataDelegate { // nonisolated: immutable
	func urlSession(
		_: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
		completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
	) {
		let failure: NativeInlineImageError? = if let response = response as? HTTPURLResponse,
		                                          let url = response.url, Self.isHTTP(url),
		                                          (200 ..< 300).contains(response.statusCode)
		{
			if response.mimeType?.lowercased().hasPrefix("image/") != true {
				.unsupportedContent
			} else if response.expectedContentLength > Int64(maximumBytes) {
				.bodyTooLarge
			} else {
				nil
			}
		} else {
			.invalidResponse
		}
		state.withLock { $0.failure = failure }
		completionHandler(failure == nil ? .allow : .cancel)
	}

	func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let cancel = state.withLock { state in
			guard state.failure == nil else { return true }
			guard data.count <= maximumBytes - state.data.count else {
				state.failure = .bodyTooLarge
				state.data = Data()
				return true
			}
			state.data.append(data)
			return false
		}
		if cancel {
			dataTask.cancel()
		}
	}

	func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
		let finished = state.withLock { state in
			let continuation = state.continuation
			state.continuation = nil
			let result: Result<Data, any Error> = if let failure = state.failure {
				.failure(failure)
			} else if let error {
				.failure(error)
			} else {
				.success(state.data)
			}
			state.data = Data()
			return (continuation, result)
		}
		finished.0?.resume(with: finished.1)
	}

	func urlSession(
		_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
		newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
	) {
		let allowed = state.withLock { state in
			state.redirects += 1
			return state.redirects <= 5 && request.url.map(Self.isHTTP) == true
		}
		completionHandler(allowed ? request : nil)
	}
}
