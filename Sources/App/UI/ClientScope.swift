// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@MainActor
protocol ClientScoped: AnyObject {
	var clientId: String? { get }
}

@MainActor
protocol ChannelScoped: ClientScoped {
	var channelId: String? { get }
}
