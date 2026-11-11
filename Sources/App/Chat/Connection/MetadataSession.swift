// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Posted when profiles on a session changed, once per batch or debounce tick.
/// Names are casefolded. `isReset` says every profile on the session went.
struct SessionProfilesDidChange: NotificationCenter.MainActorMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.sessionProfilesDidChange")

	private nonisolated static let nicknamesKey = "nicknames"
	private nonisolated static let channelsKey = "channels"
	private nonisolated static let resetKey = "isReset"

	let subject: ServerSession
	let nicknames: Set<String>
	let channels: Set<String>
	let isReset: Bool

	static func makeMessage(_ notification: Notification) -> Self? {
		guard let subject = notification.object as? ServerSession else { return nil }

		return Self(
			subject: subject,
			nicknames: notification.userInfo?[nicknamesKey] as? Set<String> ?? [],
			channels: notification.userInfo?[channelsKey] as? Set<String> ?? [],
			isReset: notification.userInfo?[resetKey] as? Bool ?? false
		)
	}

	static func makeNotification(_ message: Self) -> Notification {
		Notification(name: name, object: message.subject, userInfo: [
			nicknamesKey: message.nicknames,
			channelsKey: message.channels,
			resetKey: message.isReset,
		])
	}

	@MainActor func post() {
		NotificationCenter.default.post(self, subject: subject)
	}
}

/// What became of a request to set one of the user's own keys.
nonisolated enum MetadataSetOutcome: Sendable, Equatable {
	/// The server stored this value, which may differ from the one sent, or
	/// removed the key for `nil`.
	case stored(String?)
	/// The server asked to wait; Glasstual tries again by itself.
	case rateLimited(retryAfter: Int)
	case failed(MetadataFailure)
}

/// Why a metadata request did not complete.
nonisolated enum MetadataFailure: Sendable, Equatable {
	case invalidTarget
	case keyInvalid
	case keyNoPermission
	case limitReached(maximumKeys: Int?)
	case valueInvalid(maximumBytes: Int?)
	case rateLimitExhausted
	case subcommandInvalid
	case notConnected
	case unsupported

	var localizedDescription: String {
		switch self {
		case .invalidTarget: String(localized: .Metadata.failureInvalidTarget)
		case .keyInvalid: String(localized: .Metadata.failureKeyInvalid)
		case .keyNoPermission: String(localized: .Metadata.failureKeyNoPermission)
		case let .limitReached(maximum?): String(localized: .Metadata.failureLimitReachedCount(maximum))
		case .limitReached(nil): String(localized: .Metadata.failureLimitReached)
		case let .valueInvalid(maximum?): String(localized: .Metadata.failureValueInvalidBytes(maximum))
		case .valueInvalid(nil): String(localized: .Metadata.failureValueInvalid)
		case .rateLimitExhausted: String(localized: .Metadata.failureRateLimitExhausted)
		case .subcommandInvalid: String(localized: .Metadata.failureSubcommandInvalid)
		case .notConnected: String(localized: .Metadata.failureNotConnected)
		case .unsupported: String(localized: .Metadata.unsupported)
		}
	}
}

/// A `METADATA` subcommand, as `/metadata` and the session send them.
nonisolated enum MetadataSubcommand: String, Sendable, CaseIterable {
	case get, list, set, clear, sub, unsub, subs, sync

	var wireName: String {
		rawValue.uppercased()
	}
}

/// A query whose answer arrives in a batch, kept in the order it was sent so a
/// reply without a label can be matched to the oldest one for its target.
struct MetadataQuery {
	let subcommand: MetadataSubcommand
	/// The target as the session compares it: `*` for the user, casefolded otherwise.
	let target: String
	/// Whether `/metadata` asked, so the entries are printed.
	let printsOutput: Bool
	var printedEntries = 0
	/// The keys a `SUBS` listing collected.
	var listedKeys: [String] = []
	/// Told when the batch closes, with the failure if the server refused.
	var completion: (@MainActor (MetadataFailure?) -> Void)?
}

/// One of the user's own keys on its way to the server.
struct PendingMetadataSet {
	/// The latest value asked for; `nil` removes the key.
	var value: String?
	var attempts = 0
	/// Sent, and no reply yet. A rate-limited set waits on its timer instead.
	var isAwaitingReply = true
	var retryTimer: SessionTimer?
	var observer: (@MainActor (MetadataSetOutcome) -> Void)?
}

/// A target the server asked to synchronize later.
struct MetadataSyncRetry {
	var attempts = 0
	var timer: SessionTimer?
}

/** Everything `draft/metadata-2` keeps for one connection.

 Remote values live on the users and channels themselves; this holds the
 bookkeeping around them. All of it is in memory and goes on disconnect. */
struct MetadataSession {
	static let maximumQueries = 64
	static let maximumSyncAttempts = 6
	static let maximumRateLimitAttempts = 4
	/// How long profile changes are gathered before views hear about them.
	static let refreshDelay: TimeInterval = 0.1

	/// Keys the server confirmed subscribing to.
	var subscribed: Set<String> = []
	/// The keys of the last `SUB`, in the order sent, for `TOO_MANY_SUBS`.
	var requestedSubscription: [String] = []
	/// The user's own values as the server holds them, by key.
	var ownWireValues: [String: String] = [:]
	/// The registration burst has told what the server holds for the user.
	var ownProfileLoaded = false
	var pendingSets: [String: PendingMetadataSet] = [:]
	/// Keys with a set awaiting its reply, oldest first.
	var setOrder: [String] = []
	var syncRetries: [String: MetadataSyncRetry] = [:]
	var queries: [MetadataQuery] = []
	var changedNicknames: Set<String> = []
	var changedChannels: Set<String> = []
	var refreshTimer: SessionTimer?
	/// Paces retries and the refresh; tests step their own.
	var clock = TimerClock.continuous

	/// Forgets the connection's metadata. The clock stays.
	mutating func reset() {
		stopTimers()
		self = MetadataSession(clock: clock)
	}

	func stopTimers() {
		refreshTimer?.stop()
		for pending in pendingSets.values {
			pending.retryTimer?.stop()
		}
		for retry in syncRetries.values {
			retry.timer?.stop()
		}
	}

	private init(clock: TimerClock) {
		self.clock = clock
	}

	init() {}
}
