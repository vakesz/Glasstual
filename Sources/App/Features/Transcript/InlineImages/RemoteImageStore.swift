// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Posted after an image arrives, so whatever draws images from the store
/// draws again.
struct RemoteImageStoreDidChange: SubjectMessage {
	typealias Subject = RemoteImageStore

	nonisolated static let name = Notification.Name("Glasstual.remoteImageStoreDidChange")

	let subject: RemoteImageStore
}

/** Small images a server names, fetched on demand and kept in memory: the
 icons networks advertise through ISUPPORT `ICON` and the profile pictures
 people set with `draft/metadata-2`.

 The address comes from a server, so every download is the inline-image one:
 HTTP or HTTPS only, a refusal of loopback, private and link-local hosts before
 and after resolution, a byte ceiling and bounded decoding, through the proxy of
 the session that asked, with no failover. ``Configuration`` sets the ceilings,
 how many images are kept and how many fetches run at once.

 Images are kept by address, so every session that names the same address
 shares one image, and the oldest unused one goes first. Fetches in flight and
 failures are kept per address and route: an image that failed through one
 proxy may still arrive directly for another session, and a direct fetch never
 stands in for a proxied one. A failure is retried after the configured
 interval, or not at all.

 Each request names its owner, the session it was made for. Releasing an owner
 drops the images and fetches no other owner still names, which is how a
 disconnect forgets the profile pictures it asked for. */
@MainActor
final class RemoteImageStore {
	struct Configuration {
		var limits: InlineImageLimits
		/// Images kept at once.
		var capacity: Int
		/// Fetches running at once; further requests wait their turn.
		var maximumConcurrentFetches: Int
		/// Requests that may wait for a fetch slot. Past this they are dropped.
		var maximumQueuedFetches = 512
		/// How long a failed fetch is not tried again, or `nil` for never.
		var failureRetryInterval: Duration?
		/// When a route may fetch at all.
		var fetchPolicy: @MainActor @Sendable (InlineImageRoute) -> InlineImageRoute.FetchPolicy
	}

	private struct Request: Hashable {
		let url: URL
		let route: InlineImageRoute
	}

	let configuration: Configuration

	private let protocolClasses: [URLProtocol.Type]
	private let hostResolver: InlineImageHostResolver
	private let now: @MainActor () -> ContinuousClock.Instant
	private let notificationCenter: NotificationCenter

	private var images: [URL: NSImage] = [:]
	/// Least recently used first.
	private var order: [URL] = []
	private var owners: [URL: Set<String>] = [:]
	private var failures: [Request: ContinuousClock.Instant] = [:]
	private var tasks: [Request: Task<Void, Never>] = [:]
	private var queue: [Request] = []
	private let subscriptions = NotificationSubscriptions()

	init(
		configuration: Configuration,
		protocolClasses: [URLProtocol.Type] = [],
		hostResolver: InlineImageHostResolver? = nil,
		notificationCenter: NotificationCenter = .default,
		now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
	) {
		self.configuration = configuration
		self.protocolClasses = protocolClasses
		// A stubbed protocol never reaches the network, so there is nothing to resolve.
		self.hostResolver = hostResolver ?? (protocolClasses.isEmpty ? .system : .literalOnly)
		self.notificationCenter = notificationCenter
		self.now = now
	}

	isolated deinit {
		for task in tasks.values {
			task.cancel()
		}
	}

	/// The image already fetched for `url`, or `nil` while there is none.
	func image(for url: URL) -> NSImage? {
		guard let image = images[url] else { return nil }
		touch(url)

		return image
	}

	/** Starts fetching `url` over `route` for `owner`, unless the route fetches
	 nothing on its own, the image is held, or that fetch is in flight, waiting
	 or known to fail. */
	func request(_ url: URL, route: InlineImageRoute, owner: String) {
		guard configuration.fetchPolicy(route) == .automatic else { return }
		owners[url, default: []].insert(owner)

		let request = Request(url: url, route: route)
		guard images[url] == nil, tasks[request] == nil, queue.contains(request) == false,
		      hasRecentlyFailed(request) == false
		else { return }
		guard LinkSchemeRules.isWebURL(url),
		      InlineImageHostPolicy.verdict(forHost: url.host(percentEncoded: false)) != .refused
		else {
			failures[request] = now()
			return
		}

		if tasks.count < configuration.maximumConcurrentFetches {
			start(request)
		} else if queue.count < configuration.maximumQueuedFetches {
			queue.append(request)
		}
	}

	/// Whether a fetch for `url` over `route` is under way.
	func isFetching(_ url: URL, route: InlineImageRoute) -> Bool {
		tasks[Request(url: url, route: route)] != nil
	}

	/// Whether a fetch for `url` over `route` waits for a slot.
	func isQueued(_ url: URL, route: InlineImageRoute) -> Bool {
		queue.contains(Request(url: url, route: route))
	}

	/// Releases the owner a `Message` names, whenever one is posted that names
	/// one: a session that disconnected forgets the pictures it asked for.
	func releaseOwner<Message: NotificationCenter.MainActorMessage>(
		on messageType: Message.Type,
		owner: @escaping @MainActor (Message) -> String?
	) where Message.Subject: AnyObject {
		subscriptions.observe(messageType, center: notificationCenter) { [weak self] message in
			guard let name = owner(message) else { return }
			self?.release(owner: name)
		}
	}

	/// Forgets what `owner` asked for: images and fetches no other owner names
	/// go away.
	func release(owner: String) {
		var abandoned: Set<URL> = []

		for (url, names) in owners where names.contains(owner) {
			let remaining = names.subtracting([owner])
			if remaining.isEmpty {
				owners.removeValue(forKey: url)
				abandoned.insert(url)
			} else {
				owners[url] = remaining
			}
		}

		guard abandoned.isEmpty == false else { return }

		for url in abandoned {
			images.removeValue(forKey: url)
		}
		order.removeAll { abandoned.contains($0) }
		queue.removeAll { abandoned.contains($0.url) }
		for (request, task) in tasks where abandoned.contains(request.url) {
			task.cancel()
			tasks.removeValue(forKey: request)
		}
		startQueued()
	}

	// MARK: - Fetching

	private func hasRecentlyFailed(_ request: Request) -> Bool {
		guard let failedAt = failures[request] else { return false }
		guard let interval = configuration.failureRetryInterval, failedAt.duration(to: now()) >= interval else { return true }

		failures.removeValue(forKey: request)

		return false
	}

	private func start(_ request: Request) {
		let limits = configuration.limits
		let protocolClasses = protocolClasses
		let hostResolver = hostResolver
		tasks[request] = Task { [weak self] in
			let image: NSImage?
			do {
				let data = try await InlineImageTransfer.download(
					request.url,
					limits: limits,
					route: request.route,
					protocolClasses: protocolClasses,
					resolver: hostResolver
				)
				let preview = try await InlineImageDecoder.prepare(data, limits: limits)
				image = NSImage(data: preview.data)
			} catch is CancellationError {
				return
			} catch {
				image = nil
			}
			self?.finish(request, image: image)
		}
	}

	private func finish(_ request: Request, image: NSImage?) {
		guard tasks.removeValue(forKey: request) != nil else { return }
		defer { startQueued() }

		guard let image else {
			failures[request] = now()
			return
		}

		let url = request.url
		guard images[url] == nil, owners[url] != nil else { return }
		images[url] = image
		touch(url)
		while order.count > configuration.capacity {
			let evicted = order.removeFirst()
			images.removeValue(forKey: evicted)
			owners.removeValue(forKey: evicted)
		}
		RemoteImageStoreDidChange(subject: self).post(on: notificationCenter)
	}

	private func startQueued() {
		while tasks.count < configuration.maximumConcurrentFetches, queue.isEmpty == false {
			let next = queue.removeFirst()
			guard images[next.url] == nil, tasks[next] == nil else { continue }
			start(next)
		}
	}

	private func touch(_ url: URL) {
		if let index = order.firstIndex(of: url) {
			order.remove(at: index)
		}
		order.append(url)
	}
}

extension RemoteImageStore.Configuration {
	/// Network icons: a few kilobytes each, one per network.
	static let networkIcons: Self = {
		var limits = InlineImageLimits()
		limits.maximumEncodedBytes = 256 * 1024
		limits.maximumDimension = 2048
		limits.maximumPixels = 1024 * 1024
		limits.maximumFrames = 1
		limits.maximumDecodedBytes = 32 * 1024 * 1024
		limits.thumbnailDimension = 256

		return Self(
			limits: limits,
			capacity: 32,
			maximumConcurrentFetches: 4,
			failureRetryInterval: nil,
			fetchPolicy: { $0.networkIconFetch }
		)
	}()

	/// Profile pictures: one frame, no animation, small thumbnails, many people.
	static let avatars: Self = {
		var limits = InlineImageLimits()
		limits.maximumEncodedBytes = 256 * 1024
		limits.maximumDimension = 1024
		limits.maximumPixels = 1024 * 1024
		limits.maximumFrames = 1
		limits.maximumDecodedBytes = 16 * 1024 * 1024
		limits.thumbnailDimension = 256

		return Self(
			limits: limits,
			capacity: 512,
			maximumConcurrentFetches: 4,
			failureRetryInterval: .seconds(10 * 60),
			fetchPolicy: { $0.avatarFetch }
		)
	}()
}
