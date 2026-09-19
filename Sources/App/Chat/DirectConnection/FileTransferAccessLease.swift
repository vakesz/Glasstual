// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Each recipient owns an independent scope count, including across retries.
final nonisolated class FileTransferAccessLease: Sendable { // nonisolated: immutable
	let url: URL
	let isAccessing: Bool
	private let stopAccess: @Sendable (URL) -> Void

	init(
		url: URL,
		startAccess: @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
		stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
	) {
		self.url = url
		self.stopAccess = stopAccess
		isAccessing = startAccess(url)
	}

	deinit {
		if isAccessing {
			stopAccess(url)
		}
	}
}
