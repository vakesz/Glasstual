// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Synchronization

/** Why one inline image was refused.

 Nothing here reaches the reader: a refused preview leaves the link as it was
 and the reason goes to the unified log. ``logDescription`` is therefore a
 diagnostic and stays untranslated — a `LocalizedError` here would put four
 English literals where the catalogs are the only source of user-facing text. */
nonisolated enum InlineImageError: Error, Sendable {
	case invalidResponse
	case unsupportedContent
	case bodyTooLarge
	case resourceLimit

	var logDescription: String {
		switch self {
		case .invalidResponse: "the server returned an invalid response"
		case .unsupportedContent: "the address does not contain a supported image"
		case .bodyTooLarge: "the body exceeds the download limit"
		case .resourceLimit: "the preview exceeds the resource limits"
		}
	}
}

/// Bounds both work in flight and previews handed to a transcript. The receiver
/// must release a line's reservations when it discards that line's attachments.
@MainActor
final class InlineImageLoader {
	static let shared = InlineImageLoader()

	private struct Key: Hashable {
		let view: String
		let line: String
		let link: String
	}

	private struct Entry {
		let reservation: UUID
		var task: Task<Void, Never>?
	}

	private let limits: InlineImageLimits
	private let budget: InlineImageBudget
	private let protocolClasses: [URLProtocol.Type]
	private var entries: [Key: Entry] = [:]

	init(
		limits: InlineImageLimits = .init(),
		budget: InlineImageBudget = .shared,
		protocolClasses: [URLProtocol.Type] = []
	) {
		self.limits = limits
		self.budget = budget
		self.protocolClasses = protocolClasses
	}

	isolated deinit {
		for entry in entries.values {
			if let task = entry.task {
				task.cancel()
			} else {
				budget.release(entry.reservation)
			}
		}
	}

	/// Returns nil on admission rejection, and reports the rejection to completion.
	/// No work is queued. Cancellation deliberately does not invoke completion.
	@discardableResult
	func load(
		url: URL,
		viewIdentifier: String,
		lineNumber: String,
		linkIdentifier: String,
		completion: @escaping @MainActor (Result<TranscriptInlineImage, Error>) -> Void
	) -> UUID? {
		let key = Key(view: viewIdentifier, line: lineNumber, link: linkIdentifier)
		guard LinkParser.isWebURL(url) else {
			completion(.failure(InlineImageError.unsupportedContent))
			return nil
		}
		guard entries[key] == nil,
		      let reservation = budget.reserve(view: viewIdentifier, bytes: limits.workingByteCount)
		else {
			completion(.failure(InlineImageError.resourceLimit))
			return nil
		}
		let limits = limits
		let protocolClasses = protocolClasses
		let budget = budget
		let task = Task { [weak self] in
			var retained = false
			defer {
				if !retained {
					budget.release(reservation)
				}
				if self?.entries[key]?.reservation == reservation {
					if retained {
						self?.entries[key]?.task = nil
					} else {
						self?.entries.removeValue(forKey: key)
					}
				}
			}
			do {
				let data = try await InlineImageTransfer.download(
					url,
					limits: limits,
					protocolClasses: protocolClasses
				)
				let preview = try await InlineImageDecoder.prepare(data, limits: limits)
				try Task.checkCancellation()
				guard self?.entries[key]?.reservation == reservation else { return }
				budget.retain(reservation, bytes: preview.residentByteCount)
				retained = true
				// Mark resident before invoking a receiver that may synchronously clear it.
				self?.entries[key]?.task = nil
				completion(.success(TranscriptInlineImage(
					lineNumber: lineNumber,
					linkIdentifier: linkIdentifier,
					sourceURL: url,
					imageData: preview.data
				)))
			} catch is CancellationError {
				return
			} catch {
				guard !Task.isCancelled, self?.entries[key]?.reservation == reservation else { return }
				self?.entries.removeValue(forKey: key)
				budget.release(reservation)
				completion(.failure(error))
			}
		}
		entries[key] = Entry(reservation: reservation, task: task)
		return reservation
	}

	/// Also releases completed previews. Call only when their attachments are gone.
	func cancelLoads(forView viewIdentifier: String) {
		for key in entries.keys.filter({ $0.view == viewIdentifier }) {
			remove(key)
		}
	}

	/// Call before replacing/removing a line, including edits that reuse its ID.
	func cancelLoads(forView viewIdentifier: String, lineNumber: String) {
		for key in entries.keys.filter({ $0.view == viewIdentifier && $0.line == lineNumber }) {
			remove(key)
		}
	}

	func cancelAll() {
		for key in Array(entries.keys) {
			remove(key)
		}
	}

	/// Releases a refused completion without touching a replacement's reservation.
	func cancelLoad(_ requestIdentifier: UUID) {
		guard let key = entries.first(where: { $0.value.reservation == requestIdentifier })?.key else { return }
		remove(key)
	}

	private func remove(_ key: Key) {
		guard let entry = entries.removeValue(forKey: key) else { return }
		if let task = entry.task {
			// The worker, not cancellation, releases memory still used by ImageIO.
			task.cancel()
		} else {
			budget.release(entry.reservation)
		}
	}
}

@MainActor
final class InlineImageBudget {
	static let shared = InlineImageBudget()

	private struct Reservation {
		let view: String
		var bytes: Int
		var active = true
	}

	private let maximumRequests: Int
	private let maximumViewRequests: Int
	private let maximumBytes: Int
	private let maximumViewBytes: Int
	private let maximumEntries: Int
	private let maximumViewEntries: Int
	private var reservations: [UUID: Reservation] = [:]

	init(
		maximumRequests: Int = 4, maximumViewRequests: Int = 2,
		maximumBytes: Int = 768 * 1024 * 1024, maximumViewBytes: Int = 384 * 1024 * 1024,
		maximumEntries: Int = 128, maximumViewEntries: Int = 32
	) {
		self.maximumRequests = maximumRequests
		self.maximumViewRequests = maximumViewRequests
		self.maximumBytes = maximumBytes
		self.maximumViewBytes = maximumViewBytes
		self.maximumEntries = maximumEntries
		self.maximumViewEntries = maximumViewEntries
	}

	var entryCount: Int {
		reservations.count
	}

	var activeCount: Int {
		reservations.values.filter(\.active).count
	}

	var reservedByteCount: Int {
		reservations.values.reduce(0) { $0 + $1.bytes }
	}

	func reserve(view: String, bytes: Int?) -> UUID? {
		let local = reservations.values.filter { $0.view == view }
		guard let bytes, bytes > 0,
		      reservations.count < maximumEntries, local.count < maximumViewEntries,
		      activeCount < maximumRequests, local.filter(\.active).count < maximumViewRequests,
		      bytes <= maximumBytes, reservedByteCount <= maximumBytes - bytes,
		      bytes <= maximumViewBytes, local.reduce(0, { $0 + $1.bytes }) <= maximumViewBytes - bytes
		else { return nil }
		let identifier = UUID()
		reservations[identifier] = Reservation(view: view, bytes: bytes)
		return identifier
	}

	func retain(_ identifier: UUID, bytes: Int) {
		guard var reservation = reservations[identifier] else { return }
		reservation.bytes = min(reservation.bytes, max(0, bytes))
		reservation.active = false
		reservations[identifier] = reservation
	}

	func release(_ identifier: UUID) {
		reservations.removeValue(forKey: identifier)
	}
}

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

	private init(maximumBytes: Int) {
		self.maximumBytes = maximumBytes
	}

	@concurrent
	static func download(_ url: URL, limits: InlineImageLimits,
	                     protocolClasses: [URLProtocol.Type]) async throws -> Data
	{
		try Task.checkCancellation()
		guard LinkParser.isWebURL(url) else { throw InlineImageError.unsupportedContent }
		guard limits.workingByteCount != nil else { throw InlineImageError.resourceLimit }
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
		let delegate = InlineImageTransfer(maximumBytes: limits.maximumEncodedBytes)
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

nonisolated extension InlineImageTransfer: URLSessionDataDelegate { // nonisolated: immutable
	func urlSession(
		_: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
		completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
	) {
		let failure: InlineImageError? = if let response = response as? HTTPURLResponse,
		                                    let url = response.url, LinkParser.isWebURL(url),
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
			return state.redirects <= 5 && request.url.map(LinkParser.isWebURL) == true
		}
		completionHandler(allowed ? request : nil)
	}
}
