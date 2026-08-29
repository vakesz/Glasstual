/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

@objc(TLOInternetAddressLookupDelegate)
@MainActor
public protocol InternetAddressLookupDelegate: AnyObject {
	func internetAddressLookupReturnedAddress(_ address: String)
	func internetAddressLookupFailed()
}

@objc(TLOInternetAddressLookup)
@MainActor
public final class InternetAddressLookup: NSObject {
	private static let requestTimeout: TimeInterval = 30
	private static let firstPartySourceURL = URL(string: "https://api.ipify.org")!
	private static let thirdPartySourceURLs = [
		URL(string: "https://wtfismyip.com/text")!,
		URL(string: "https://canhazip.com/")!,
		URL(string: "https://ifconfig.me/ip")!,
	]
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "InternetAddressLookup"
	)

	@objc(IPv4AddressIsValid) public var ipv4AddressIsValid = true
	@objc(IPv6AddressIsValid) public var ipv6AddressIsValid = true

	private weak var requestDelegate: InternetAddressLookupDelegate?
	private var session: URLSession?
	private var lookupTask: Task<Void, Never>?
	private var address: String?
	/** Identifies the lookup a completion belongs to so that a cancelled or superseded
	 request cannot report back to the delegate. */
	private var lookupGeneration: UInt64 = 0

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(delegate:)")
	}

	@objc(initWithDelegate:)
	public init(delegate: InternetAddressLookupDelegate) {
		requestDelegate = delegate

		super.init()
	}

	@objc public func performLookup() {
		/* A second request while one is in flight restarts rather than aborting the app;
		 two concurrent DCC offers can reach this. */
		cancelLookup()

		lookupGeneration &+= 1
		let generation = lookupGeneration

		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.timeoutIntervalForRequest = Self.requestTimeout
		configuration.timeoutIntervalForResource = Self.requestTimeout

		let session = URLSession(configuration: configuration)
		let sourceURL = addressSourceURL

		self.session = session
		lookupTask = Task { [weak self] in
			do {
				let (data, response) = try await session.data(from: sourceURL)

				self?.completeLookup(generation: generation, data: data, response: response, error: nil)
			} catch {
				self?.completeLookup(generation: generation, data: nil, response: nil, error: error)
			}
		}
	}

	@objc public func cancelLookup() {
		/* Retiring the generation stops the in-flight completion from reporting a
		 cancellation to the delegate as a lookup failure. */
		lookupGeneration &+= 1
		teardownConnection()
	}

	@objc(addressFromData:response:allowIPv4:allowIPv6:)
	public nonisolated static func address( // nonisolated: pure
		from data: Data?,
		response: URLResponse?,
		allowIPv4: Bool,
		allowIPv6: Bool
	) -> String? {
		guard
			let response = response as? HTTPURLResponse,
			response.statusCode == 200,
			let data,
			!data.isEmpty,
			data.count <= 1024,
			let address = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		else {
			return nil
		}

		guard
			(allowIPv4 && address.isIPv4Address)
			|| (allowIPv6 && address.isIPv6Address)
		else {
			return nil
		}

		return address
	}

	private var addressSourceURL: URL {
		if TextualPreferences.fileTransferIPAddressDetectionMethod() == .routerAndThirdParty {
			return Self.thirdPartySourceURLs.randomElement()!
		}

		return Self.firstPartySourceURL
	}

	private func completeLookup(generation: UInt64, data: Data?, response: URLResponse?, error: Error?) {
		guard generation == lookupGeneration else { return }

		if let error {
			Self.logger.error("Lookup failed: \(error.localizedDescription, privacy: .public)")
		} else {
			address = Self.address(
				from: data,
				response: response,
				allowIPv4: ipv4AddressIsValid,
				allowIPv6: ipv6AddressIsValid
			)
		}

		teardownConnection()
		informDelegate()
		address = nil
	}

	private func teardownConnection() {
		lookupTask?.cancel()
		lookupTask = nil

		session?.invalidateAndCancel()
		session = nil
	}

	private func informDelegate() {
		if let address {
			requestDelegate?.internetAddressLookupReturnedAddress(address)
		} else {
			requestDelegate?.internetAddressLookupFailed()
		}
	}
}
