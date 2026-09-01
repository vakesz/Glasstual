/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated struct TranscriptTextTraits: OptionSet, Equatable, Sendable { // nonisolated: value
	let rawValue: UInt8

	static let bold = Self(rawValue: 1 << 0)
	static let italic = Self(rawValue: 1 << 1)
	static let monospace = Self(rawValue: 1 << 2)
	static let strikethrough = Self(rawValue: 1 << 3)
	static let underline = Self(rawValue: 1 << 4)
	static let highlighted = Self(rawValue: 1 << 5)
}

nonisolated enum TranscriptRunColor: Equatable, Sendable { // nonisolated: value
	case palette(Int)
	case rgb(TranscriptThemeColor)
}

nonisolated enum TranscriptRunAction: Equatable, Sendable { // nonisolated: value
	case link(URL)
	case channel(String)
	case nickname(String)
}

nonisolated struct TranscriptTextRun: Equatable, Sendable { // nonisolated: value
	var text: String
	var traits: TranscriptTextTraits = []
	var foreground: TranscriptRunColor?
	var background: TranscriptRunColor?
	var action: TranscriptRunAction?
}

nonisolated struct TranscriptBody: Equatable, Sendable { // nonisolated: value
	var plainText = ""
	var runs: [TranscriptTextRun] = []
	var links: [LinkParserResult] = []
	var mentionedNicknames: [String] = []
	var isHighlight = false
}

nonisolated enum TranscriptMarker: Equatable, Sendable { // nonisolated: value
	case date(String)
	case currentSession(String)
	case unread(String)
}

/// One complete native transcript row. It is independent of AppKit so render
/// jobs can build it concurrently and the view can restyle it without parsing
/// source text or markup again.
nonisolated struct TranscriptLine: Equatable, Sendable { // nonisolated: value
	var lineNumber: String
	var receivedAt: Date
	var timestamp: String
	var nickname: String?
	var formattedNickname: String
	var memberType: LogLineMemberType
	var lineType: LogLineType
	var command: String
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryState: LogLineDeliveryState
	var deliveryFailureReason: String?
	var reactions: [String: [String]]
	var markers: [TranscriptMarker]
	var body: TranscriptBody

	var isMessage: Bool {
		lineType == .privateMessage || lineType == .action || lineType == .notice
	}
}

nonisolated struct TranscriptInlineImage: Equatable, Sendable { // nonisolated: value
	var lineNumber: String
	var linkIdentifier: String
	var sourceURL: URL
	var imageData: Data
}
