// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network
import Synchronization

/// URLSession invokes the delegate outside actor isolation. Its only mutable
/// storage is a bounded value; no task or unbounded stream is created per chunk.
final nonisolated class InlineImageTransfer: NSObject, Sendable { // nonisolated: immutable
	private struct State {
		var data = Data()
		var failure: InlineImageError?
		var continuation: CheckedContinuation<Data, any Error>?
		var redirects = 0
		/// Set once the surrounding task was cancelled and the session torn
		/// down, so a continuation installed afterwards is not left waiting on
		/// a data task that will never run.
		var isCancelled = false
	}

	private let state = Mutex(State())
	private let maximumBytes: Int
	/// `nil` when a proxy resolves names, so nothing is looked up on this Mac.
	private let resolver: InlineImageHostResolver?
	/// The only host a redirect may lead to, or nil when any permitted host may.
	private let redirectHost: String?

	private init(maximumBytes: Int, resolver: InlineImageHostResolver?, redirectHost: String?) {
		self.maximumBytes = maximumBytes
		self.resolver = resolver
		self.redirectHost = redirectHost
	}

	/** Fetches `url` over `route`.

	 A proxied route sends the host name to the proxy: it is not looked up here,
	 and the address the connection reached is the proxy's, so only the spelling
	 of the host is checked, and on the reader's own proxy a redirect may not
	 leave the host the link named. An unavailable route fails before any work. */
	@concurrent
	static func download(_ url: URL, limits: InlineImageLimits,
	                     route: InlineImageRoute,
	                     protocolClasses: [URLProtocol.Type],
	                     resolver: InlineImageHostResolver = .system) async throws -> Data
	{
		try Task.checkCancellation()
		guard route != .unavailable else { throw InlineImageError.proxyUnavailable }
		guard LinkSchemeRules.isWebURL(url) else { throw InlineImageError.unsupportedContent }
		let localResolver = route.resolvesNamesLocally ? resolver : nil
		guard await InlineImageHostPolicy.permits(url, resolver: localResolver) else {
			throw InlineImageError.hostNotAllowed
		}
		try Task.checkCancellation()
		guard limits.workingByteCount != nil else { throw InlineImageError.resourceLimit }
		let configuration = configuration(for: route, protocolClasses: protocolClasses)
		let delegate = InlineImageTransfer(
			maximumBytes: limits.maximumEncodedBytes,
			resolver: localResolver,
			redirectHost: route.followsRedirectsToOtherHosts ? nil : url.host()?.lowercased()
		)
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

	/// An ephemeral session that keeps nothing, routed through the proxy
	/// `route` names with no failover to a direct connection.
	static func configuration(
		for route: InlineImageRoute,
		protocolClasses: [URLProtocol.Type] = []
	) -> URLSessionConfiguration {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.urlCache = nil
		configuration.httpCookieStorage = nil
		configuration.urlCredentialStorage = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.timeoutIntervalForRequest = 30
		configuration.timeoutIntervalForResource = 60
		let proxies = route.proxyConfigurations
		if !proxies.isEmpty {
			configuration.proxyConfigurations = proxies
		}
		if !protocolClasses.isEmpty {
			configuration.protocolClasses = protocolClasses
		}
		return configuration
	}
}

nonisolated extension InlineImageTransfer: URLSessionDataDelegate { // nonisolated: immutable
	func urlSession(
		_: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
		completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
	) {
		let failure: InlineImageError? = if let response = response as? HTTPURLResponse,
		                                    let url = response.url, LinkSchemeRules.isWebURL(url),
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

	/** Metrics arrive after the last byte and before completion. A connection that
	 reached a refused address, as a rebound name would, turns the download into
	 a failure and drops what was read.

	 Through a configured proxy the address reached is the proxy's own, often
	 loopback for Tor, and says nothing about the origin, so it is not checked. */
	func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
		guard resolver != nil else { return }
		let refused = metrics.transactionMetrics.contains { transaction in
			transaction.isProxyConnection == false
				&& InlineImageHostPolicy.permitsRemoteAddress(transaction.remoteAddress) == false
		}
		guard refused else { return }
		state.withLock { state in
			state.failure = .hostNotAllowed
			state.data = Data()
		}
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
		let withinLimit = state.withLock { state in
			state.redirects += 1
			return state.redirects <= 5 && request.url.map(LinkSchemeRules.isWebURL) == true
		}
		guard redirectHost.map({ $0 == request.url?.host()?.lowercased() }) ?? true else {
			state.withLock { $0.failure = .hostNotAllowed }
			completionHandler(nil)
			return
		}
		guard withinLimit, let target = request.url else {
			completionHandler(nil)
			return
		}
		/* A redirect is as free to name a private host as the original link, so
		 the target is held to the same policy before it is followed. */
		let resolver = resolver
		Task {
			let allowed = await InlineImageHostPolicy.permits(target, resolver: resolver)
			completionHandler(allowed ? request : nil)
		}
	}
}
