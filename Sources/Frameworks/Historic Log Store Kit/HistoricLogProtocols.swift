/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2020 Codeux Software, LLC & respective contributors.
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

@objc(HLSHistoricLogServerProtocol)
public nonisolated protocol HistoricLogServerProtocol: AnyObject { // nonisolated: xpc-shim
	@objc(openDatabaseInDirectory:withCompletionBlock:)
	func openDatabase(
		inDirectory databaseDirectory: String,
		withCompletionBlock completionBlock: (@Sendable (Bool) -> Void)?
	)

	@objc(writeLogLine:)
	func writeLogLine(_ logLine: LogLineXPC)

	@objc(saveDataWithCompletionBlock:)
	func saveData(completionBlock: (@Sendable () -> Void)?)

	@objc(forgetView:)
	func forgetView(_ viewIdentifier: String)

	@objc(resetDataForView:)
	func resetData(forView viewIdentifier: String)

	@objc(fetchEntriesForView:ascending:fetchLimit:limitToDate:withCompletionBlock:)
	func fetchEntries(
		forView viewIdentifier: String,
		ascending: Bool,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	)

	@objc(fetchEntriesForView:withUniqueIdentifier:beforeFetchLimit:afterFetchLimit:limitToDate:withCompletionBlock:)
	func fetchEntries(
		forView viewIdentifier: String,
		withUniqueIdentifier uniqueIdentifier: String,
		beforeFetchLimit fetchLimitBefore: UInt,
		afterFetchLimit fetchLimitAfter: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	)

	@objc(fetchEntriesForView:beforeUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:)
	func fetchEntries(
		forView viewIdentifier: String,
		beforeUniqueIdentifier uniqueIdentifier: String,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	)

	@objc(fetchEntriesForView:afterUniqueIdentifier:fetchLimit:limitToDate:withCompletionBlock:)
	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifier: String,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	)

	@objc(fetchEntriesForView:afterUniqueIdentifier:beforeUniqueIdentifier:fetchLimit:withCompletionBlock:)
	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifierAfter: String,
		beforeUniqueIdentifier uniqueIdentifierBefore: String,
		fetchLimit: UInt,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	)

	@objc(setMaximumLineCount:)
	func setMaximumLineCount(_ maximumLineCount: UInt)
}

@objc(HLSHistoricLogClientProtocol)
public nonisolated protocol HistoricLogClientProtocol: AnyObject, Sendable { // nonisolated: xpc-shim
	@objc(willDeleteUniqueIdentifiers:inView:)
	func willDeleteUniqueIdentifiers(_ uniqueIdentifiers: [String], inView viewIdentifier: String)
}

public nonisolated enum HistoricLogInterface { // nonisolated: value
	/// The five fetches that reply with an array. NSXPC derives an allowlist
	/// from a declared class but not from a collection of one, so each has to
	/// be told what its reply may contain. Both ends of the connection call
	/// this, so the two allowlists cannot drift apart.
	public static func configure(_ interface: NSXPCInterface) -> Bool {
		guard let replyClasses = NSSet(objects: NSArray.self, LogLineXPC.self) as? Set<AnyHashable> else {
			assertionFailure("Unable to bridge the historic-log XPC reply classes")

			return false
		}

		let fetchSelectors: [Selector] = [
			#selector((any HistoricLogServerProtocol)
				.fetchEntries(forView:ascending:fetchLimit:limitTo:withCompletionBlock:)),
			#selector((any HistoricLogServerProtocol)
				.fetchEntries(
					forView:withUniqueIdentifier:beforeFetchLimit:afterFetchLimit:limitTo:withCompletionBlock:
				)),
			#selector((any HistoricLogServerProtocol)
				.fetchEntries(forView:beforeUniqueIdentifier:fetchLimit:limitTo:withCompletionBlock:)),
			#selector((any HistoricLogServerProtocol)
				.fetchEntries(forView:afterUniqueIdentifier:fetchLimit:limitTo:withCompletionBlock:)),
			#selector((any HistoricLogServerProtocol)
				.fetchEntries(forView:afterUniqueIdentifier:beforeUniqueIdentifier:fetchLimit:withCompletionBlock:)),
		]

		for selector in fetchSelectors {
			interface.setClasses(replyClasses, for: selector, argumentIndex: 0, ofReply: true)
		}

		return true
	}
}
