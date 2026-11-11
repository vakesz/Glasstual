// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The requests the session makes of `draft/metadata-2`, and their answers.

 A `SET` of one of the user's own keys is answered by a lone `761` or `766`;
 the stored value is the server's, never the one typed. Queries are answered
 in a `metadata` batch named after their target. Without labels, a `FAIL` is
 matched to the pending set for its key first and then to the oldest query of
 its kind; anything unmatched is printed the usual way. */
extension ServerSession {
	/// The longest value `/metadata` prints.
	private static let maximumPrintedValueLength = 300

	// MARK: - The user's own keys

	/** Sets one of the user's own keys, or removes it for `nil`.

	 A set the server rate-limited is retried by itself; a newer value replaces
	 the queued one and keeps its timer. `remembering` stores the value in the
	 server's configuration, so it is set again on the next connect. */
	func setOwnMetadata(
		key: String,
		value: String?,
		remembering: Bool = true,
		observer: (@MainActor (MetadataSetOutcome) -> Void)? = nil
	) {
		guard isCapabilityEnabled(.metadata) else {
			observer?(.failed(.unsupported))
			return
		}
		guard canSendMetadata else {
			observer?(.failed(.notConnected))
			return
		}

		if remembering {
			rememberProfilePreference { $0[key] = value }
		}

		if var pending = metadata.pendingSets[key], pending.isAwaitingReply == false {
			pending.value = value
			pending.observer = observer ?? pending.observer
			metadata.pendingSets[key] = pending
			return
		}

		metadata.pendingSets[key] = PendingMetadataSet(value: value, observer: observer)
		writeOwnMetadataSet(key: key, value: value)
	}

	/// Removes every key the user set, and remembers the profile as empty.
	func clearOwnMetadata(completion: (@MainActor (MetadataFailure?) -> Void)? = nil) {
		guard isCapabilityEnabled(.metadata) else {
			completion?(.unsupported)
			return
		}
		guard canSendMetadata else {
			completion?(.notConnected)
			return
		}

		rememberProfilePreference { $0 = ServerProfilePreference() }
		sendMetadataQuery(.clear, target: "*", arguments: [], printsOutput: false, completion: completion)
	}

	// MARK: - Queries

	/// Sends a query whose answer arrives in a batch for `target`.
	func sendMetadataQuery(
		_ subcommand: MetadataSubcommand,
		target: String,
		arguments: [String],
		printsOutput: Bool,
		completion: (@MainActor (MetadataFailure?) -> Void)? = nil
	) {
		if metadata.queries.count >= MetadataSession.maximumQueries {
			metadata.queries.removeFirst()
		}
		metadata.queries.append(MetadataQuery(
			subcommand: subcommand,
			target: subcommand == .subs ? "*" : metadataTargetKey(target),
			printsOutput: printsOutput,
			completion: completion
		))
		if printsOutput {
			printDebugInformation(toConsole: String(localized: .Metadata.queryHeader(target, subcommand.wireName)))
		}
		send(.metadata, arguments: [target, subcommand.wireName] + arguments)
	}

	/// Asks for everything a target holds, as the server's sync answer.
	func requestMetadataSync(for target: String) {
		sendMetadataQuery(.sync, target: target, arguments: [], printsOutput: false)
	}

	func completeMetadataQuery(for target: String, failure: MetadataFailure?) {
		guard let index = metadata.queries.firstIndex(where: { $0.target == target && $0.subcommand != .subs }) else {
			return
		}

		let query = metadata.queries.remove(at: index)
		if query.printsOutput, query.printedEntries == 0, failure == nil {
			printDebugInformation(toConsole: String(localized: .Metadata.noMetadata))
		}
		if let failure, query.printsOutput {
			printDebugInformation(toConsole: failure.localizedDescription)
		}
		query.completion?(failure)
	}

	func completeSubscriptionListing() {
		guard let index = metadata.queries.firstIndex(where: { $0.subcommand == .subs }) else { return }

		let query = metadata.queries.remove(at: index)
		let keys = query.listedKeys.sorted()
		metadata.subscribed = Set(keys)
		if query.printsOutput {
			printDebugInformation(toConsole: keys.isEmpty
				? String(localized: .Metadata.noSubscriptions)
				: String(localized: .Metadata.subscriptions(keys.joined(separator: ", "))))
		}
		query.completion?(nil)
	}

	/// Prints one entry of a query `/metadata` is waiting on.
	func printMetadataQueryEntry(target: String, key: String, visibility: String?, value: String?) {
		let targetKey = metadataTargetKey(target)
		guard let index = metadata.queries.firstIndex(where: { $0.target == targetKey && $0.printsOutput }) else { return }

		metadata.queries[index].printedEntries += 1
		printDebugInformation(toConsole: Self.formattedMetadataEntry(key: key, visibility: visibility, value: value))
	}

	/// `key = value`, sanitized and cut, with a visibility other than `*`.
	static func formattedMetadataEntry(key: String, visibility: String?, value: String?) -> String {
		let safeKey = ControlCharacterDisposition.singleLine(key)

		guard let value else {
			return String(localized: .Metadata.keyNotSet(safeKey))
		}

		var line = ControlCharacterDisposition.singleLine((value as NSString).stripIRCEffects)
		if line.count > maximumPrintedValueLength {
			line = String(line.prefix(maximumPrintedValueLength)) + "…"
		}

		if let visibility, visibility != "*" {
			return String(localized: .Metadata.keyValueRestricted(
				safeKey, line, ControlCharacterDisposition.singleLine(visibility)
			))
		}

		return String(localized: .Metadata.keyValue(safeKey, line))
	}

	// MARK: - Replies to sets

	/// A `761` or `766`: it may answer a set of the user's own key.
	func resolveMetadataReply(target: String, key: String, value: String?) {
		if metadataTargetKey(target) == "*", metadata.pendingSets[key]?.isAwaitingReply == true {
			completeOwnMetadataSet(key: key, stored: value)
		}
		storeMetadata(target: target, key: key, value: value)
	}

	private func completeOwnMetadataSet(key: String, stored value: String?) {
		guard let pending = metadata.pendingSets.removeValue(forKey: key) else { return }
		pending.retryTimer?.stop()
		metadata.setOrder.removeAll { $0 == key }
		pending.observer?(.stored(value))
	}

	private func failOwnMetadataSet(key: String, failure: MetadataFailure) {
		guard let pending = metadata.pendingSets.removeValue(forKey: key) else { return }
		pending.retryTimer?.stop()
		metadata.setOrder.removeAll { $0 == key }
		pending.observer?(.failed(failure))
	}

	private func writeOwnMetadataSet(key: String, value: String?) {
		var arguments = ["*", MetadataSubcommand.set.wireName, key]
		if let value {
			arguments.append(value)
		}
		metadata.pendingSets[key]?.isAwaitingReply = true
		metadata.setOrder.removeAll { $0 == key }
		metadata.setOrder.append(key)
		send(.metadata, arguments: arguments)
	}

	/** Remembers the user's choice in the configuration.

	 Written in place rather than through `updateConfig(_:for:)`: the change is
	 the user's own, made live, and announcing it as a reconfiguration would ask
	 an open Server Properties sheet whether to throw its edits away. The next
	 save writes it, and that sheet's own save keeps it. */
	private func rememberProfilePreference(_ change: (inout ServerProfilePreference) -> Void) {
		var preference = config.serverProfile ?? ServerProfilePreference()
		change(&preference)
		guard preference != config.serverProfile else { return }
		config.serverProfile = preference
		environment.chatSession?.savePeriodically()
	}

	// MARK: - Failures

	/// A `FAIL METADATA`. Reports whether the session consumed it.
	func receiveMetadataFailure(_ message: Message) -> Bool {
		guard message.remoteCommand == .fail, message.params.count >= 3,
		      RemoteCommand(wireName: message.params[0]) == .metadata,
		      let code = MetadataReplyCode(rawValue: message.params[1])
		else { return false }

		let context = Array(message.params.dropFirst(2).dropLast())

		switch code {
		case .keyInvalid:
			return receiveKeyRefusal(key: context.first, failure: .keyInvalid, droppingSubscription: true)
		case .keyNoPermission:
			return receiveKeyRefusal(key: context.dropFirst().first, failure: .keyNoPermission, droppingSubscription: false)
		case .keyNotSet:
			guard let key = context.dropFirst().first, metadata.pendingSets[key]?.value == nil,
			      metadata.pendingSets[key]?.isAwaitingReply == true
			else { return false }
			completeOwnMetadataSet(key: key, stored: nil)
			storeMetadata(target: "*", key: key, value: nil)
			return true
		case .limitReached:
			guard let key = metadata.setOrder.first else { return false }
			failOwnMetadataSet(key: key, failure: .limitReached(maximumKeys: metadataValues.maximumKeys))
			return true
		case .valueInvalid:
			guard let key = metadata.setOrder.first else { return false }
			failOwnMetadataSet(key: key, failure: .valueInvalid(maximumBytes: metadataValues.maximumValueBytes))
			return true
		case .rateLimited:
			guard context.count >= 2 else { return false }
			return receiveMetadataRateLimit(key: context[1], retryAfter: context.count > 2 ? Int(context[2]) : nil)
		case .tooManySubscriptions:
			guard let key = context.first, let index = metadata.requestedSubscription.firstIndex(of: key) else {
				return false
			}
			metadata.requestedSubscription.removeSubrange(index...)
			return true
		case .invalidTarget:
			guard let target = context.first else { return false }
			let key = metadataTargetKey(target)
			metadata.syncRetries.removeValue(forKey: key)?.timer?.stop()
			completeMetadataQuery(for: key, failure: .invalidTarget)
			return true
		case .subcommandInvalid:
			guard let query = metadata.queries.first else { return false }
			completeMetadataQuery(for: query.target, failure: .subcommandInvalid)
			return true
		}
	}

	private func receiveKeyRefusal(key: String?, failure: MetadataFailure, droppingSubscription: Bool) -> Bool {
		guard let key else { return false }

		/* A set is something the user just asked for, so it is the likelier
		 owner of a refusal naming its key than a subscription. */
		if metadata.pendingSets[key]?.isAwaitingReply == true {
			failOwnMetadataSet(key: key, failure: failure)
			return true
		}

		if metadata.requestedSubscription.contains(key) {
			/* A key without permission is still subscribed; an invalid one is not. */
			if droppingSubscription {
				metadata.requestedSubscription.removeAll { $0 == key }
				return true
			}
			return false
		}

		if let index = metadata.queries.firstIndex(where: \.printsOutput) {
			metadata.queries[index].printedEntries += 1
			printDebugInformation(toConsole: String(localized: .Metadata.keyRefused(
				ControlCharacterDisposition.singleLine(key), failure.localizedDescription
			)))
			return true
		}

		return false
	}

	/** `RATE_LIMITED`: the set goes again after the server's delay, or after
	 5, 10, 20 and 40 seconds when it named none, and fails after that. */
	private func receiveMetadataRateLimit(key: String, retryAfter: Int?) -> Bool {
		guard var pending = metadata.pendingSets[key] else { return false }

		pending.attempts += 1
		metadata.setOrder.removeAll { $0 == key }

		guard pending.attempts <= MetadataSession.maximumRateLimitAttempts else {
			metadata.pendingSets[key] = pending
			failOwnMetadataSet(key: key, failure: .rateLimitExhausted)
			return true
		}

		let delay = retryAfter.map { min(max($0, 1), 300) } ?? 5 << (pending.attempts - 1)
		pending.isAwaitingReply = false
		pending.retryTimer?.stop()
		pending.retryTimer = SessionTimer.once(after: TimeInterval(delay), clock: metadata.clock) { [weak self] in
			guard let self, let latest = metadata.pendingSets[key], latest.isAwaitingReply == false else { return }
			writeOwnMetadataSet(key: key, value: latest.value)
		}
		metadata.pendingSets[key] = pending
		pending.observer?(.rateLimited(retryAfter: delay))

		return true
	}

	// MARK: - Postponed sync

	/** `774`: the server will answer for `target` later. The wait is what it
	 asked for, at least one second and at most five minutes; one that answers
	 an earlier retry doubles the floor, and the sixth gives up. */
	func scheduleMetadataSync(for target: String, retryAfter: Int?) {
		let key = metadataTargetKey(target)
		var retry = metadata.syncRetries[key] ?? MetadataSyncRetry()
		retry.attempts += 1
		retry.timer?.stop()
		if let query = metadata.queries.first(where: { $0.target == key }), query.printsOutput {
			printDebugInformation(toConsole: String(localized: .Metadata.syncLater(target)))
			metadata.queries.removeAll { $0.target == key && $0.subcommand == query.subcommand }
		} else {
			completeMetadataQuery(for: key, failure: nil)
		}

		guard retry.attempts <= MetadataSession.maximumSyncAttempts else {
			metadata.syncRetries.removeValue(forKey: key)
			printDebugInformation(toConsole: String(localized: .Metadata.syncGaveUp(target)))
			return
		}

		let floor = retry.attempts > 1 ? 5 << (retry.attempts - 1) : 1
		let delay = min(max(retryAfter ?? 5, floor), 300)
		retry.timer = SessionTimer.once(after: TimeInterval(delay), clock: metadata.clock) { [weak self] in
			guard let self, canSendMetadata else { return }
			requestMetadataSync(for: target)
		}
		metadata.syncRetries[key] = retry
	}
}
