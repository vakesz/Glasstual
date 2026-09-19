// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private let internetAddressLookupLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "InternetAddressLookup"
)

/// Asks a public address service what this Mac looks like from the internet,
/// which is the address a DCC offer has to name.
enum InternetAddressLookup {
	private static let requestTimeout: TimeInterval = 30
	private nonisolated static let responseByteLimit = 1024
	private static let firstPartySourceURL = URL(string: "https://api.ipify.org")!
	private static let thirdPartySourceURLs = [
		URL(string: "https://wtfismyip.com/text")!,
		URL(string: "https://canhazip.com/")!,
		URL(string: "https://ifconfig.me/ip")!,
	]

	/// The address the configured source reports, or `nil` when no usable one
	/// came back — a refusal, an unreadable body, or a cancelled request.
	static func address() async -> String? {
		await address(from: sourceURL)
	}

	static func address(from sourceURL: URL) async -> String? {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.timeoutIntervalForRequest = requestTimeout
		configuration.timeoutIntervalForResource = requestTimeout

		let session = URLSession(configuration: configuration)
		defer { session.invalidateAndCancel() }

		do {
			let (bytes, response) = try await session.bytes(from: sourceURL)
			guard let http = response as? HTTPURLResponse, http.statusCode == 200,
			      response.expectedContentLength <= responseByteLimit
			else {
				throw URLError(.badServerResponse)
			}

			/* Read the body as it arrives rather than after it: a chunked
			 response that never terminates would otherwise be refused only when
			 the resource timeout ran out. */
			var data = Data()
			for try await byte in bytes {
				guard data.count < responseByteLimit else { throw URLError(.dataLengthExceedsMaximum) }
				data.append(byte)
			}

			return address(from: data, response: response)
		} catch {
			internetAddressLookupLogger.error("Lookup failed: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// The address a response body names, or `nil` when it names none.
	nonisolated static func address(from data: Data?, response: URLResponse?) -> String? { // nonisolated: pure
		guard
			let response = response as? HTTPURLResponse,
			response.statusCode == 200,
			let data,
			!data.isEmpty,
			data.count <= responseByteLimit,
			let address = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines),
			address.isIPv4Address || address.isIPv6Address
		else {
			return nil
		}

		return address
	}

	private static var sourceURL: URL {
		if SettingsKeys.FileTransfers.ipAddressDetectionMethod.value == .routerAndThirdParty {
			return thirdPartySourceURLs.randomElement()!
		}

		return firstPartySourceURL
	}
}
