// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** `draft/metadata-2`: the names, pictures and colours people set on the
 server, kept on the users and channels they describe.

 Only the three profile keys are stored, bounded per value, and only for users
 in the directory, the user and the channels the session is in. Everything is
 cleared on disconnect and on `CAP DEL`. Views hear about changes through
 ``SessionProfilesDidChange``, once per batch or after a short pause. */
extension ServerSession {
	/// The server's limits, from what the current offer says.
	var metadataValues: MetadataCapabilityValues {
		MetadataCapabilityValues(
			capabilityValues: capabilityNegotiation.offeredCapabilities[MetadataCapabilityValues.capabilityName] ?? []
		)
	}

	/// Whether metadata commands may go out now.
	var canSendMetadata: Bool {
		isCapabilityEnabled(.metadata) && (isLoggedIn || metadataValues.beforeConnect)
	}

	/// The target the session compares replies against: `*` for the user.
	func metadataTargetKey(_ target: String) -> String {
		target == "*" || nicknameIsMyself(target) ? "*" : casefoldNickname(target)
	}

	// MARK: - Negotiation and subscription

	/// The capability was acknowledged or withdrawn.
	func noteMetadataCapability(enabled: Bool) {
		guard enabled else {
			clearAllProfiles()
			metadata.reset()
			return
		}

		if isLoggedIn == false, metadataValues.beforeConnect {
			subscribeToProfileKeys()
		}
	}

	/// The welcome arrived: subscribe before the join burst, so it carries values.
	func metadataDidReceiveWelcome() {
		guard isCapabilityEnabled(.metadata), metadata.subscribed.isEmpty, metadata.requestedSubscription.isEmpty else {
			return
		}

		subscribeToProfileKeys()
	}

	/// The end of the message of the day closes the registration burst.
	func metadataRegistrationBurstDidEnd() {
		markOwnProfileLoaded()
	}

	/// Subscribes to the profile keys the server allows, in order of preference.
	func subscribeToProfileKeys() {
		guard isCapabilityEnabled(.metadata), environment.settings.showsServerProfiles else { return }

		var keys = MetadataKey.profileKeys.filter { metadata.subscribed.contains($0) == false }
		if let maximum = metadataValues.maximumSubscriptions {
			keys = Array(keys.prefix(max(0, maximum - metadata.subscribed.count)))
		}

		guard keys.isEmpty == false else { return }

		metadata.requestedSubscription = keys
		send(.metadata, arguments: ["*", MetadataSubcommand.sub.wireName] + keys)
	}

	/// Stops the subscription and forgets everyone else's profile.
	func unsubscribeFromProfileKeys() {
		let keys = MetadataKey.profileKeys.filter { metadata.subscribed.contains($0) }

		if keys.isEmpty == false, isCapabilityEnabled(.metadata) {
			send(.metadata, arguments: ["*", MetadataSubcommand.unsub.wireName] + keys)
		}
		metadata.requestedSubscription.removeAll()
		clearAllProfiles(keepingOwn: true)
	}

	/// The Show Server Profiles setting changed.
	func serverProfilesSettingDidChange() {
		guard canSendMetadata else { return }

		if environment.settings.showsServerProfiles {
			subscribeToProfileKeys()
			for channel in conversationList where channel.isChannel && channel.isActive {
				requestMetadataSync(for: channel.name)
			}
		} else {
			unsubscribeFromProfileKeys()
		}
	}

	// MARK: - Inbound

	/// `METADATA <target> <key> <visibility> [:<value>]`.
	func receiveMetadata(_ message: Message) {
		guard message.params.count >= 3 else { return }

		let target = message.params[0]
		let key = message.params[1]
		let value = message.params.count > 3 ? message.params[3] : nil

		printMetadataQueryEntry(target: target, key: key, visibility: message.params[2], value: value)
		storeMetadata(target: target, key: key, value: value)
	}

	/// The numerics that answer metadata commands, apart from the WHOIS entry.
	func handleMetadataNumeric(_ numeric: ServerNumeric, message: Message) {
		switch numeric {
		case .keyvalue:
			guard message.params.count >= 4 else { return }
			let value = message.params.count > 4 ? message.params[4] : ""
			printMetadataQueryEntry(target: message.params[1], key: message.params[2], visibility: message.params[3], value: value)
			resolveMetadataReply(target: message.params[1], key: message.params[2], value: value)
		case .keynotset:
			guard message.params.count >= 3 else { return }
			printMetadataQueryEntry(target: message.params[1], key: message.params[2], visibility: nil, value: nil)
			resolveMetadataReply(target: message.params[1], key: message.params[2], value: nil)
		case .metadatasubok:
			let keys = Self.metadataKeys(in: message)
			metadata.subscribed.formUnion(keys)
			metadata.requestedSubscription.removeAll { keys.contains($0) }
		case .metadataunsubok:
			metadata.subscribed.subtract(Self.metadataKeys(in: message))
		case .metadatasubs:
			let keys = Self.metadataKeys(in: message)
			if let index = metadata.queries.firstIndex(where: { $0.subcommand == .subs }) {
				metadata.queries[index].listedKeys.append(contentsOf: keys)
			}
		case .metadatasynclater:
			guard message.params.count >= 2 else { return }
			scheduleMetadataSync(for: message.params[1], retryAfter: message.params.count > 2 ? Int(message.params[2]) : nil)
		default:
			break
		}
	}

	/// A `metadata` or `metadata-subs` batch closed: its query is complete.
	func closeMetadataBatch(_ batch: MessageBatch) {
		if batch.kind == .metadataSubs {
			completeSubscriptionListing()
		} else if let target = batch.batchParameters?.first {
			let key = metadataTargetKey(target)
			completeMetadataQuery(for: key, failure: nil)
			if metadata.syncRetries[key]?.timer?.isActive != true {
				metadata.syncRetries.removeValue(forKey: key)
			}
			if key == "*" {
				markOwnProfileLoaded()
			}
		}

		flushProfileChanges()
	}

	// MARK: - Storage

	/// Stores a profile key for the user, a member of the directory or a channel.
	func storeMetadata(target: String, key: String, value: String?) {
		guard MetadataKey.profileKeys.contains(key) else { return }

		if metadataTargetKey(target) == "*" {
			metadata.ownWireValues[key] = value
			if let myself {
				var changed = false
				modify(myself) { changed = $0.profile.apply(key: key, value: value) }
				if changed {
					noteProfileChanged(nickname: myself.nickname)
				}
			}
			return
		}

		if stringIsChannelName(target) {
			guard let channel = findConversation(target), channel.isChannel, channel.isActive else { return }
			if channel.channelProfile.apply(key: key, value: value) {
				metadata.changedChannels.insert(casefoldNickname(channel.name))
				scheduleProfileRefresh()
			}
			return
		}

		guard environment.settings.showsServerProfiles, let user = findUser(target) else { return }

		var changed = false
		modify(user) { changed = $0.profile.apply(key: key, value: value) }
		if changed {
			noteProfileChanged(nickname: user.nickname)
		}
	}

	/// Forgets every profile on the session and says so once.
	func clearAllProfiles(keepingOwn: Bool = false) {
		let ownNickname = myself?.nickname
		var nicknames: Set<String> = []

		for user in Array(userIndex.values) where user.profile.isEmpty == false {
			guard keepingOwn == false || user.nickname != ownNickname else { continue }
			modify(user) { $0.profile = UserProfile() }
			nicknames.insert(casefoldNickname(user.nickname))
		}

		var channels: Set<String> = []
		for channel in conversationList where channel.channelProfile.isEmpty == false {
			channel.channelProfile = UserProfile()
			channels.insert(casefoldNickname(channel.name))
		}

		guard nicknames.isEmpty == false || channels.isEmpty == false else { return }

		SessionProfilesDidChange(subject: self, nicknames: nicknames, channels: channels, isReset: keepingOwn == false).post()
	}

	/// The connection is gone.
	func metadataConnectionDidReset() {
		let hadProfiles = metadata.ownWireValues.isEmpty == false
			|| userIndex.values.contains { $0.profile.isEmpty == false }
		metadata.reset()
		for channel in conversationList {
			channel.channelProfile = UserProfile()
		}
		if hadProfiles {
			SessionProfilesDidChange(subject: self, nicknames: [], channels: [], isReset: true).post()
		}
	}

	/// A channel was left: its profile and any sync it waits for go.
	func metadataChannelDidDeactivate(_ channel: Conversation) {
		channel.channelProfile = UserProfile()
		let key = casefoldNickname(channel.name)
		metadata.syncRetries.removeValue(forKey: key)?.timer?.stop()
	}

	func noteProfileChanged(nickname: String) {
		metadata.changedNicknames.insert(casefoldNickname(nickname))
		scheduleProfileRefresh()
	}

	func scheduleProfileRefresh() {
		guard metadata.refreshTimer?.isActive != true else { return }

		metadata.refreshTimer = SessionTimer.once(after: MetadataSession.refreshDelay, clock: metadata.clock) { [weak self] in
			self?.flushProfileChanges()
		}
	}

	func flushProfileChanges() {
		metadata.refreshTimer?.stop()

		guard metadata.changedNicknames.isEmpty == false || metadata.changedChannels.isEmpty == false else { return }

		let message = SessionProfilesDidChange(
			subject: self,
			nicknames: metadata.changedNicknames,
			channels: metadata.changedChannels,
			isReset: false
		)
		metadata.changedNicknames.removeAll()
		metadata.changedChannels.removeAll()
		message.post()
	}

	// MARK: - The user's own profile

	/** The server has said what it holds for the user. A profile the user chose
	 for this server earlier is set again where the server's copy differs. */
	func markOwnProfileLoaded() {
		guard metadata.ownProfileLoaded == false, isCapabilityEnabled(.metadata) else { return }

		metadata.ownProfileLoaded = true

		guard let preference = config.serverProfile else { return }

		for key in MetadataKey.profileKeys where preference[key] != metadata.ownWireValues[key] {
			setOwnMetadata(key: key, value: preference[key], remembering: false)
		}
	}

	/// The keys a subscription numeric names, whether one per parameter or
	/// several in the trailing one.
	private static func metadataKeys(in message: Message) -> [String] {
		message.params.dropFirst().flatMap { $0.split(separator: " ").map(String.init) }
	}
}
