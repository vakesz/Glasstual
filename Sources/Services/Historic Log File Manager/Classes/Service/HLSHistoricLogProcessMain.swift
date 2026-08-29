/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
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

/// The object NSXPC exports for a historic log connection.
///
/// Every method is a one-line hop into `HistoricLogStore`, which owns all the
/// state. Reply blocks are already `@Sendable` in the protocol, so a reply can
/// be sent from inside the actor's task without leaving its isolation domain.
///
/// The connection stays here rather than in the store: `NSXPCConnection` is not
/// `Sendable`, and region isolation will not let the listener's connection be
/// sent into another domain. So this object also owns the remote object proxy
/// and delivers the store's queued deletion notices, which it flushes at the
/// head of every incoming call.
@objc(HLSHistoricLogProcessMain)
final class HistoricLogProcessMain: NSObject, HistoricLogServerProtocol {
	private let store: HistoricLogStore
	private let notices: HistoricLogNotices
	private weak var serviceConnection: NSXPCConnection?

	init(store: HistoricLogStore, notices: HistoricLogNotices, connection: NSXPCConnection) {
		self.store = store
		self.notices = notices
		serviceConnection = connection

		super.init()
	}

	/// A proxy for the client half of the connection. Messages sent through it
	/// are one way; nothing here waits on the client.
	private func remoteObjectProxy() -> HistoricLogClientProtocol? {
		serviceConnection?.remoteObjectProxy as? HistoricLogClientProtocol
	}

	/// Delivers whatever the store truncated since the last call.
	private func flushNotices() {
		let pending = notices.drain()

		guard pending.isEmpty == false, let proxy = remoteObjectProxy() else { return }

		for notice in pending {
			proxy.willDeleteUniqueIdentifiers(notice.uniqueIdentifiers, inView: notice.viewIdentifier)
		}
	}

	// MARK: - Database

	func openDatabase(
		inDirectory databaseDirectory: String,
		withCompletionBlock completionBlock: (@Sendable (Bool) -> Void)?
	) {
		flushNotices()

		Task { [store] in
			let opened = await store.openDatabase(inDirectory: databaseDirectory)

			completionBlock?(opened)
		}
	}

	func setMaximumLineCount(_ maximumLineCount: UInt) {
		flushNotices()

		Task { [store] in
			await store.setMaximumLineCount(maximumLineCount)
		}
	}

	func saveData(completionBlock: (@Sendable () -> Void)?) {
		flushNotices()

		Task { [store] in
			/* The reply block is an XPC reply; it has to be invoked on every path. */
			defer { completionBlock?() }

			await store.saveData()
		}
	}

	func forgetView(_ viewIdentifier: String) {
		flushNotices()

		Task { [store] in
			await store.forgetView(viewIdentifier)
		}
	}

	func resetData(forView viewIdentifier: String) {
		flushNotices()

		Task { [store] in
			await store.resetData(forView: viewIdentifier)
		}
	}

	func writeLogLine(_ logLine: LogLineXPC) {
		flushNotices()

		Task { [store] in
			await store.writeLogLine(logLine)
		}
	}

	// MARK: - Fetching

	func fetchEntries(
		forView viewIdentifier: String,
		ascending: Bool,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		flushNotices()

		Task { [store] in
			await completionBlock(
				store.fetchEntries(
					forView: viewIdentifier,
					ascending: ascending,
					fetchLimit: fetchLimit,
					limitToDate: limitToDate
				)
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		withUniqueIdentifier uniqueIdentifier: String,
		beforeFetchLimit fetchLimitBefore: UInt,
		afterFetchLimit fetchLimitAfter: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		flushNotices()

		Task { [store] in
			await completionBlock(
				store.fetchEntries(
					forView: viewIdentifier,
					aroundUniqueIdentifier: uniqueIdentifier,
					beforeFetchLimit: fetchLimitBefore,
					afterFetchLimit: fetchLimitAfter,
					limitToDate: limitToDate
				)
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		beforeUniqueIdentifier uniqueIdentifier: String,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		flushNotices()

		Task { [store] in
			await completionBlock(
				store.fetchEntries(
					forView: viewIdentifier,
					relativeTo: uniqueIdentifier,
					direction: .before,
					fetchLimit: fetchLimit,
					limitToDate: limitToDate
				)
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifier: String,
		fetchLimit: UInt,
		limitTo limitToDate: Date?,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		flushNotices()

		Task { [store] in
			await completionBlock(
				store.fetchEntries(
					forView: viewIdentifier,
					relativeTo: uniqueIdentifier,
					direction: .after,
					fetchLimit: fetchLimit,
					limitToDate: limitToDate
				)
			)
		}
	}

	func fetchEntries(
		forView viewIdentifier: String,
		afterUniqueIdentifier uniqueIdentifierAfter: String,
		beforeUniqueIdentifier uniqueIdentifierBefore: String,
		fetchLimit: UInt,
		withCompletionBlock completionBlock: @escaping @Sendable ([LogLineXPC]) -> Void
	) {
		flushNotices()

		Task { [store] in
			await completionBlock(
				store.fetchEntries(
					forView: viewIdentifier,
					afterUniqueIdentifier: uniqueIdentifierAfter,
					beforeUniqueIdentifier: uniqueIdentifierBefore,
					fetchLimit: fetchLimit
				)
			)
		}
	}
}
