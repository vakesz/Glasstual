// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** The icons networks advertise through ISUPPORT `ICON`, fetched once each.

 The address comes from a server, so the download is the inline-image one: HTTP
 or HTTPS only, a refusal of loopback, private and link-local hosts before and
 after resolution, a byte ceiling and bounded decoding. An icon is a few
 kilobytes, so the ceilings here are far below what a transcript image gets.

 Icons are kept by address, which is what makes them per network: every session
 on the same network advertises the same address and shares one image. An
 address that failed once is not tried again until the app restarts, so a
 server advertising a dead link costs one request.

 Each fetch goes through the proxy of the session that asked for it, so a
 network reached over Tor or another proxy never learns this Mac's address
 from its own icon. A session on the reader's own SOCKS5 or HTTP proxy fetches
 no icon at all (`InlineImageRoute.networkIconFetch`): that proxy resolves the
 name, so a server could point it at an address on the proxy's own network.
 Fetches in flight and failures are kept per address and
 route: an icon that failed through one proxy may still arrive directly for
 another session, and a direct fetch never stands in for a proxied one. An
 icon already held is shown to every session, since showing it sends nothing. */
@MainActor
final class NetworkIconStore {
	/// Icons kept at once; the oldest goes first.
	static let capacity = 32

	static let limits: InlineImageLimits = {
		var limits = InlineImageLimits()
		limits.maximumEncodedBytes = 256 * 1024
		limits.maximumDimension = 2048
		limits.maximumPixels = 1024 * 1024
		limits.maximumFrames = 1
		limits.maximumDecodedBytes = 32 * 1024 * 1024
		limits.thumbnailDimension = 256
		return limits
	}()

	/// Called after an icon arrives, so what draws it can draw again.
	var onChange: (@MainActor () -> Void)?

	private struct Request: Hashable {
		let url: URL
		let route: InlineImageRoute
	}

	private let protocolClasses: [URLProtocol.Type]
	private let hostResolver: InlineImageHostResolver
	private var images: [URL: NSImage] = [:]
	private var order: [URL] = []
	private var unavailable: Set<Request> = []
	private var tasks: [Request: Task<Void, Never>] = [:]

	init(protocolClasses: [URLProtocol.Type] = [], hostResolver: InlineImageHostResolver? = nil) {
		self.protocolClasses = protocolClasses
		// A stubbed protocol never reaches the network, so there is nothing to resolve.
		self.hostResolver = hostResolver ?? (protocolClasses.isEmpty ? .system : .literalOnly)
	}

	isolated deinit {
		for task in tasks.values {
			task.cancel()
		}
	}

	/// The icon already fetched for `url`, or `nil` while there is none.
	func image(for url: URL) -> NSImage? {
		images[url]
	}

	/// Starts fetching `url` over `route` unless the route fetches no icons,
	/// the icon is held, or that fetch is in flight or known to fail.
	func request(_ url: URL, route: InlineImageRoute) {
		guard route.networkIconFetch == .automatic else { return }
		let request = Request(url: url, route: route)
		guard images[url] == nil, tasks[request] == nil, unavailable.contains(request) == false else { return }
		guard LinkSchemeRules.isWebURL(url),
		      InlineImageHostPolicy.verdict(forHost: url.host(percentEncoded: false)) != .refused
		else {
			unavailable.insert(request)
			return
		}

		let limits = Self.limits
		let protocolClasses = protocolClasses
		let hostResolver = hostResolver
		tasks[request] = Task { [weak self] in
			let image: NSImage?
			do {
				let data = try await InlineImageTransfer.download(
					url,
					limits: limits,
					route: route,
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

	/// Whether an icon fetch for `url` over `route` is under way.
	func isFetching(_ url: URL, route: InlineImageRoute) -> Bool {
		tasks[Request(url: url, route: route)] != nil
	}

	private func finish(_ request: Request, image: NSImage?) {
		tasks.removeValue(forKey: request)

		guard let image else {
			unavailable.insert(request)
			return
		}

		let url = request.url
		guard images[url] == nil else { return }
		images[url] = image
		order.append(url)
		while order.count > Self.capacity {
			images.removeValue(forKey: order.removeFirst())
		}
		onChange?()
	}
}
