/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

import CoreData
import Foundation

@objc(TVCLogLineXPC)
final nonisolated class LogLineXPC: NSObject, NSSecureCoding, Sendable { // nonisolated: value
	private enum CodingKey {
		static let data = "data"
		static let uniqueIdentifier = "uniqueIdentifier"
		static let viewIdentifier = "viewIdentifier"
		static let sessionIdentifier = "sessionIdentifier"
		static let creationDate = "entryCreationDate"
	}

	@objc let data: Data
	@objc let uniqueIdentifier: String
	@objc let viewIdentifier: String
	@objc let sessionIdentifier: UInt
	@objc let creationDate: TimeInterval

	@objc(initWithLogLineData:uniqueIdentifier:viewIdentifier:sessionIdentifier:creationDate:)
	init(
		logLineData data: Data,
		uniqueIdentifier: String,
		viewIdentifier: String,
		sessionIdentifier: UInt,
		creationDate: TimeInterval
	) {
		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.sessionIdentifier = sessionIdentifier
		self.creationDate = creationDate
		super.init()
	}

	/** Fails rather than traps: one malformed row must not abort the shared service. */
	@objc(initWithManagedObject:)
	init?(managedObject: NSManagedObject) {
		guard
			let data = managedObject.value(forKey: "logLineData") as? Data,
			let uniqueIdentifier = managedObject.value(forKey: "logLineUniqueIdentifier") as? String,
			let viewIdentifier = managedObject.value(forKey: "logLineViewIdentifier") as? String
		else {
			return nil
		}

		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		sessionIdentifier = (managedObject.value(forKey: "sessionIdentifier") as? NSNumber)?.uintValue ?? 0
		creationDate = (managedObject.value(forKey: "entryCreationDate") as? NSNumber)?.doubleValue ?? 0
		super.init()
	}

	required init?(coder: NSCoder) {
		guard
			let data = coder.decodeObject(of: NSData.self, forKey: CodingKey.data) as Data?,
			let uniqueIdentifier = coder.decodeObject(of: NSString.self, forKey: CodingKey.uniqueIdentifier) as String?,
			let viewIdentifier = coder.decodeObject(of: NSString.self, forKey: CodingKey.viewIdentifier) as String?
		else {
			return nil
		}

		/* The archive crosses an XPC boundary, so a negative or non-finite
		 value has to fail the decode rather than trap the service. */
		guard let sessionIdentifier = UInt(exactly: coder.decodeInteger(forKey: CodingKey.sessionIdentifier)) else {
			return nil
		}

		let creationDate = coder.decodeDouble(forKey: CodingKey.creationDate)

		guard creationDate.isFinite, creationDate >= 0 else {
			return nil
		}

		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.sessionIdentifier = sessionIdentifier
		self.creationDate = creationDate
		super.init()
	}

	func encode(with coder: NSCoder) {
		coder.encode(data, forKey: CodingKey.data)
		coder.encode(uniqueIdentifier, forKey: CodingKey.uniqueIdentifier)
		coder.encode(viewIdentifier, forKey: CodingKey.viewIdentifier)
		coder.encode(Int(exactly: sessionIdentifier) ?? 0, forKey: CodingKey.sessionIdentifier)
		coder.encode(creationDate, forKey: CodingKey.creationDate)
	}

	static var supportsSecureCoding: Bool {
		true
	}

	override var description: String {
		"<TVCLogLineXPC \(uniqueIdentifier) - \(creationDate)>"
	}
}
