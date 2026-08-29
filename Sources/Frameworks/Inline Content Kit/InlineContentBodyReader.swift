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
import Synchronization

/// What went wrong before a body could be handed back.
public enum InlineContentBodyError: Error, Equatable, Sendable {
	/// The endpoint answered with something other than HTTP, or with nothing.
	case notHTTP
	/// The body passed the caller's byte cap; the transfer was cut off there.
	case bodyTooLarge
}

/// How many bytes of body a caller is willing to pay for.
public struct InlineContentBodyLimit: Sendable {
	/// The cap, in bytes. Zero means the caller asked for none.
	public let maximumByteCount: Int

	/// Whether a `Content-Length` over the cap refuses the transfer before a
	/// byte of body is read.
	///
	/// A caller that wants to inspect the headers itself — because the cap
	/// only applies to some of the types it accepts — leaves this off and
	/// relies on the running count instead.
	public let refusesDeclaredOverrun: Bool

	public init(maximumByteCount: Int, refusesDeclaredOverrun: Bool) {
		self.maximumByteCount = maximumByteCount
		self.refusesDeclaredOverrun = refusesDeclaredOverrun
	}

	/// No cap: the body is read to the end.
	public static let unlimited = InlineContentBodyLimit(maximumByteCount: 0, refusesDeclaredOverrun: false)
}

/// The redirect and authentication policy a request is fetched under.
public struct InlineContentRequestPolicy: Sendable {
	/// A redirect may keep the scheme or upgrade it, never downgrade it.
	public let refusesSchemeDowngrade: Bool

	/// HTTP basic and digest challenges are cancelled rather than answered:
	/// nothing here has credentials to offer, and answering only keeps a
	/// hostile endpoint's request alive.
	public let refusesHTTPAuthentication: Bool

	public init(refusesSchemeDowngrade: Bool = true, refusesHTTPAuthentication: Bool = true) {
		self.refusesSchemeDowngrade = refusesSchemeDowngrade
		self.refusesHTTPAuthentication = refusesHTTPAuthentication
	}

	public static let `default` = InlineContentRequestPolicy()
}

/// One in-flight HTTP response: the headers, and the body in the chunks the
/// network delivered them in.
///
/// Every request the inline-content service makes is triggered by a message
/// somebody else sent, so the caller reads the headers first and then decides
/// whether the body is worth reading at all. `cancel()` stops the transfer; so
/// does dropping the stream without draining it.
public struct InlineContentBodyTransfer: Sendable {
	public let response: HTTPURLResponse

	/// The body, chunk by chunk. Finishes with
	/// ``InlineContentBodyError/bodyTooLarge`` the moment the running count
	/// would pass the limit, before the offending chunk is handed over.
	public let chunks: AsyncThrowingStream<Data, any Error>

	private let limit: InlineContentBodyLimit
	private let task: URLSessionDataTask

	fileprivate init(
		response: HTTPURLResponse,
		chunks: AsyncThrowingStream<Data, any Error>,
		limit: InlineContentBodyLimit,
		task: URLSessionDataTask
	) {
		self.response = response
		self.chunks = chunks
		self.limit = limit
		self.task = task
	}

	/// Stops the transfer. Harmless once it has already finished.
	public func cancel() {
		task.cancel()
	}

	/// Whether the transfer was stopped rather than allowed to finish — by
	/// `cancel()`, by the cap, or by a cancelled caller.
	public var isCancelled: Bool {
		task.state == .canceling || (task.error as? URLError)?.code == .cancelled
	}

	/// The whole body in one piece, which is what both readers here want.
	///
	/// Nothing beyond the limit is ever buffered: the stream refuses the chunk
	/// that would cross it. Cancelling the calling task stops the transfer and
	/// throws `CancellationError` rather than handing back a truncated body.
	public func data() async throws -> Data {
		var body = Data()

		if reservation > 0 {
			body.reserveCapacity(reservation)
		}

		for try await chunk in chunks {
			try Task.checkCancellation()

			body.append(chunk)
		}

		try Task.checkCancellation()

		return body
	}

	/// What to reserve up front, believing the declared length only as far as
	/// the limit allows: a server that declares a gigabyte must not be able to
	/// make the service allocate one.
	private var reservation: Int {
		let declared = response.expectedContentLength

		guard declared > 0 else { return 0 }

		let ceiling = limit.maximumByteCount > 0 ? limit.maximumByteCount : 4 * 1024 * 1024

		return min(Int(clamping: declared), ceiling)
	}
}

/// Reads an HTTP body in the chunks the network delivers, counting as it goes.
///
/// The readers here used to iterate `URLSession.AsyncBytes` one byte at a time
/// with a `Data.append` per byte, which cost about twenty seconds per megabyte
/// — long enough that a hostile endpoint did not have to exceed any cap to
/// cost the service real time. A `URLSessionDataDelegate` hands the body over
/// in whole chunks instead, and the cap is applied to the running count before
/// each chunk is accepted, so the transfer stops at the first chunk that would
/// cross it.
public enum InlineContentBodyReader {
	/// Starts `url` and returns once the response headers have arrived.
	///
	/// Throws before the body is touched when the reply is not HTTP, when the
	/// declared length already passes a limit that refuses declared overruns,
	/// or when the request itself failed.
	public static func begin(
		_ url: URL,
		using session: URLSession,
		limit: InlineContentBodyLimit,
		policy: InlineContentRequestPolicy = .default
	) async throws -> InlineContentBodyTransfer {
		let headers = AsyncThrowingStream<HTTPURLResponse, any Error>.makeStream()
		let chunks = AsyncThrowingStream<Data, any Error>.makeStream()

		let collector = InlineContentBodyCollector(
			limit: limit,
			policy: policy,
			headers: headers.continuation,
			chunks: chunks.continuation
		)

		let task = session.dataTask(with: url)
		task.delegate = collector

		/* Whatever ends the stream — the cap, a cancelled caller, a consumer
		 that walks away — ends the transfer with it. */
		chunks.continuation.onTermination = { _ in task.cancel() }

		task.resume()

		var iterator = headers.stream.makeAsyncIterator()

		do {
			guard let response = try await iterator.next() else {
				try Task.checkCancellation()

				throw InlineContentBodyError.notHTTP
			}

			return InlineContentBodyTransfer(
				response: response,
				chunks: chunks.stream,
				limit: limit,
				task: task
			)
		} catch {
			task.cancel()

			throw error
		}
	}
}

/// The delegate behind ``InlineContentBodyReader``.
///
/// `URLSessionTaskDelegate` is declared `NS_SWIFT_SENDABLE`, so everything
/// here is either an immutable `let` — the stream continuations are themselves
/// `Sendable` — or the running byte count, which is a value behind a `Mutex`.
private final class InlineContentBodyCollector: NSObject, URLSessionDataDelegate, Sendable {
	/// What the delegate has to remember between callbacks, and nothing more.
	private struct State {
		var byteCount = 0
		var refused = false
	}

	private let limit: InlineContentBodyLimit
	private let policy: InlineContentRequestPolicy
	private let headers: AsyncThrowingStream<HTTPURLResponse, any Error>.Continuation
	private let chunks: AsyncThrowingStream<Data, any Error>.Continuation
	private let state = Mutex(State())

	init(
		limit: InlineContentBodyLimit,
		policy: InlineContentRequestPolicy,
		headers: AsyncThrowingStream<HTTPURLResponse, any Error>.Continuation,
		chunks: AsyncThrowingStream<Data, any Error>.Continuation
	) {
		self.limit = limit
		self.policy = policy
		self.headers = headers
		self.chunks = chunks
	}

	// MARK: - Body

	func urlSession(
		_: URLSession,
		dataTask _: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
	) {
		guard let response = response as? HTTPURLResponse else {
			fail(with: InlineContentBodyError.notHTTP)
			completionHandler(.cancel)

			return
		}

		/* A declared length over the cap is refused before a byte of body is
		 read. A server that declares nothing, or lies, is caught by the
		 running count below. */
		if limit.refusesDeclaredOverrun,
		   limit.maximumByteCount > 0,
		   response.expectedContentLength > Int64(limit.maximumByteCount)
		{
			fail(with: InlineContentBodyError.bodyTooLarge)
			completionHandler(.cancel)

			return
		}

		headers.yield(response)
		headers.finish()

		completionHandler(.allow)
	}

	func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
		let refused = state.withLock { state -> Bool in
			guard !state.refused else { return true }

			if limit.maximumByteCount > 0, state.byteCount + data.count > limit.maximumByteCount {
				state.refused = true

				return true
			}

			state.byteCount += data.count

			return false
		}

		guard !refused else {
			/* Finishing the stream trips `onTermination`, which cancels the
			 task: the chunk that would cross the cap is never appended and
			 nothing more is asked for. */
			chunks.finish(throwing: InlineContentBodyError.bodyTooLarge)

			return
		}

		chunks.yield(data)
	}

	func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
		/* A refusal already ended both streams with the reason for it; the
		 cancellation it caused is not a second, truer answer. */
		guard !state.withLock({ $0.refused }) else { return }

		guard let error else {
			headers.finish()
			chunks.finish()

			return
		}

		headers.finish(throwing: error)
		chunks.finish(throwing: error)
	}

	// MARK: - Policy

	func urlSession(
		_: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection _: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping @Sendable (URLRequest?) -> Void
	) {
		guard policy.refusesSchemeDowngrade else {
			completionHandler(request)

			return
		}

		let originalScheme = task.originalRequest?.url?.scheme?.lowercased()
		let redirectedScheme = request.url?.scheme?.lowercased()
		let allowed = redirectedScheme == "https" || redirectedScheme == "http" && originalScheme == "http"

		completionHandler(allowed ? request : nil)
	}

	func urlSession(
		_: URLSession,
		task _: URLSessionTask,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		let method = challenge.protectionSpace.authenticationMethod
		let isPassword = method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest

		if policy.refusesHTTPAuthentication, isPassword {
			completionHandler(.cancelAuthenticationChallenge, nil)
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}

	// MARK: - Failure

	/// Ends both streams with `error`, for the header failures that happen
	/// before the caller ever sees a response.
	private func fail(with error: any Error) {
		state.withLock { $0.refused = true }

		headers.finish(throwing: error)
		chunks.finish(throwing: error)
	}
}
