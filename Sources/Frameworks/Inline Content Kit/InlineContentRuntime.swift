/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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

@objc(ICLMediaType)
public enum InlineContentMediaType: UInt {
	case unknown = 0
	case image
	case video
	case videoGif
	case other
}

@objc
public protocol InlineContentProcessHandling: AnyObject {
	func finalize(module: InlineContentModule, error: NSError?)
	func cancel(module: InlineContentModule)
	func deferModule(_ module: InlineContentModule, as type: InlineContentMediaType, performCheck: Bool)
}

public enum InlineContentPreferences {
	public struct Values: Sendable {
		public let maximumImageFileSize: UInt64
		public let maximumHeight: UInt
		public let maximumWidth: UInt
		public let limitBasicsToFiles: Bool

		public init(
			maximumImageFileSize: UInt64,
			maximumHeight: UInt,
			maximumWidth: UInt,
			limitBasicsToFiles: Bool
		) {
			self.maximumImageFileSize = maximumImageFileSize
			self.maximumHeight = maximumHeight
			self.maximumWidth = maximumWidth
			self.limitBasicsToFiles = limitBasicsToFiles
		}
	}

	private struct Provider: @unchecked Sendable {
		let load: () -> Values
	}

	private static let lock = NSLock()
	private nonisolated(unsafe) static var provider = Provider {
		Values(maximumImageFileSize: 2 * 1_048_576, maximumHeight: 0, maximumWidth: 0, limitBasicsToFiles: false)
	}

	public static func install(_ load: @escaping () -> Values) {
		lock.withLock { provider = Provider(load: load) }
	}

	public static var current: Values {
		lock.withLock { provider }.load()
	}
}
