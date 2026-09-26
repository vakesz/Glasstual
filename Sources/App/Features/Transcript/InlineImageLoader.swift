// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

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
		guard LinkSchemeRules.isWebURL(url) else {
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
