/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import os

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

	private weak var requestDelegate: TLOInternetAddressLookupDelegate?
	private var session: URLSession?
	private var connection: URLSessionDataTask?
	private var address: String?

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(delegate:)")
	}

	@objc(initWithDelegate:)
	public init(delegate: TLOInternetAddressLookupDelegate) {
		requestDelegate = delegate

		super.init()
	}

	@objc public func performLookup() {
		precondition(connection == nil, "A lookup is already in progress")

		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.timeoutIntervalForRequest = Self.requestTimeout
		configuration.timeoutIntervalForResource = Self.requestTimeout

		let session = URLSession(configuration: configuration)
		let sourceURL = addressSourceURL

		self.session = session
		connection = session.dataTask(with: sourceURL) { [weak self] data, response, error in
			Task { @MainActor [weak self] in
				self?.completeLookup(data: data, response: response, error: error)
			}
		}
		connection?.resume()
	}

	@objc public func cancelLookup() {
		teardownConnection()
	}

	@objc(addressFromData:response:allowIPv4:allowIPv6:)
	public nonisolated static func address(
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

		let bridgedAddress = address as NSString

		guard
			(allowIPv4 && bridgedAddress.isIPv4Address)
			|| (allowIPv6 && bridgedAddress.isIPv6Address)
		else {
			return nil
		}

		return address
	}

	private var addressSourceURL: URL {
		if TPCPreferences.fileTransferIPAddressDetectionMethod() == .routerAndThirdParty {
			return Self.thirdPartySourceURLs.randomElement()!
		}

		return Self.firstPartySourceURL
	}

	private func completeLookup(data: Data?, response: URLResponse?, error: Error?) {
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
		connection?.cancel()
		connection = nil

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
