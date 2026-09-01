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

nonisolated enum HistoricLogAttribute: String { // nonisolated: value
	case entryCreationDate
	case entryIdentifier
	case logLineData
	case logLineUniqueIdentifier
	case logLineViewIdentifier
	case sessionIdentifier
}

/// The value stored in Core Data between the archive and application models.
/// It is a native `Sendable` value because history no longer crosses XPC.
nonisolated struct HistoricLogEntry: Sendable { // nonisolated: value
	let data: Data
	let uniqueIdentifier: String
	let viewIdentifier: String
	let sessionIdentifier: UInt
	let creationDate: TimeInterval

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
	}

	/// One malformed historic row is discarded without affecting the store.
	init?(managedObject: NSManagedObject) {
		guard
			let data = managedObject.value(forKey: HistoricLogAttribute.logLineData.rawValue) as? Data,
			let uniqueIdentifier = managedObject.value(
				forKey: HistoricLogAttribute.logLineUniqueIdentifier.rawValue
			) as? String,
			let viewIdentifier = managedObject.value(
				forKey: HistoricLogAttribute.logLineViewIdentifier.rawValue
			) as? String,
			let sessionNumber = managedObject.value(
				forKey: HistoricLogAttribute.sessionIdentifier.rawValue
			) as? NSNumber,
			let sessionIdentifier = UInt(exactly: sessionNumber.int64Value),
			let creationNumber = managedObject.value(
				forKey: HistoricLogAttribute.entryCreationDate.rawValue
			) as? NSNumber,
			case let creationDate = creationNumber.doubleValue,
			creationDate.isFinite,
			creationDate >= 0
		else {
			return nil
		}

		self.data = data
		self.uniqueIdentifier = uniqueIdentifier
		self.viewIdentifier = viewIdentifier
		self.sessionIdentifier = sessionIdentifier
		self.creationDate = creationDate
	}
}
