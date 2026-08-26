/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
import os

@objc(ICLHelpers)
final class InlineContentHelpers: NSObject {
	private static let logger = Logger(
		subsystem: "com.vakesz.glasstual.InlineContentLoader",
		category: "JSON"
	)

	private static let jsonSession: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpShouldSetCookies = false
		configuration.httpCookieAcceptPolicy = .never
		return URLSession(configuration: configuration)
	}()

	private class func cancelledTask() -> URLSessionDataTask {
		let task = jsonSession.dataTask(with: URL(string: "about:blank")!)
		task.cancel()
		return task
	}

	@objc(URLWithString:)
	class func url(with address: String) -> URL? {
		URL(string: address.hasPrefix("//") ? "https:\(address)" : address)
	}

	@objc
	class var genericValidationFailedError: NSError {
		NSError(
			domain: inlineContentErrorDomain,
			code: 1003,
			userInfo: [NSLocalizedDescriptionKey: "Validation failed"]
		)
	}

	@objc(requestJSONObject:ofType:inHierarchy:fromURL:completionBlock:)
	class func requestJSONObject(
		_ objectKey: String,
		ofType objectType: AnyClass,
		inHierarchy hierarchy: [String]?,
		from url: URL,
		completionBlock: @escaping @Sendable (Any?) -> Void
	) -> URLSessionDataTask {
		requestJSONData(from: url) { success, data in
			guard success, var context = data else { return completionBlock(nil) }

			for key in hierarchy ?? [] {
				guard let nested = context[key] as? [String: Any] else { return completionBlock(nil) }
				context = nested
			}

			guard
				let value = context[objectKey],
				let object = value as? NSObject,
				object.isKind(of: objectType)
			else {
				return completionBlock(nil)
			}

			completionBlock(value)
		}
	}

	@objc(requestJSONObject:ofType:inHierarchy:fromAddress:completionBlock:)
	class func requestJSONObject(
		_ objectKey: String,
		ofType objectType: AnyClass,
		inHierarchy hierarchy: [String]?,
		fromAddress address: String,
		completionBlock: @escaping @Sendable (Any?) -> Void
	) -> URLSessionDataTask {
		guard let url = url(with: address) else {
			completionBlock(nil)
			return cancelledTask()
		}

		return requestJSONObject(
			objectKey,
			ofType: objectType,
			inHierarchy: hierarchy,
			from: url,
			completionBlock: completionBlock
		)
	}

	@objc(requestJSONDataFromURL:completionBlock:)
	class func requestJSONData(
		from url: URL,
		completionBlock: @escaping @Sendable (Bool, [String: Any]?) -> Void
	) -> URLSessionDataTask {
		let task = jsonSession.dataTask(with: url) { data, response, error in
			guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else {
				if let error {
					logger.error("Request failed: \(error.localizedDescription, privacy: .public)")
				}
				return completionBlock(false, nil)
			}

			do {
				guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
					return completionBlock(false, nil)
				}
				completionBlock(true, object)
			} catch {
				logger.error("Failed to decode response: \(error.localizedDescription, privacy: .public)")
				completionBlock(false, nil)
			}
		}

		task.resume()
		return task
	}

	@objc(requestJSONDataFromAddress:completionBlock:)
	class func requestJSONData(
		fromAddress address: String,
		completionBlock: @escaping @Sendable (Bool, [String: Any]?) -> Void
	) -> URLSessionDataTask {
		guard let url = url(with: address) else {
			completionBlock(false, nil)
			return cancelledTask()
		}

		return requestJSONData(from: url, completionBlock: completionBlock)
	}
}

extension NSString {
	@objc(isDomain:)
	func icl_isDomain(_ domain: String) -> Bool {
		isEqual(to: domain)
	}

	@objc(isDomainOrSubdomain:)
	func icl_isDomainOrSubdomain(_ domain: String) -> Bool {
		isEqual(to: domain) || hasSuffix(".\(domain)")
	}
}
