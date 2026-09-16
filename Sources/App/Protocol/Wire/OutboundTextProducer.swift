/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Produces one wire chunk at a time, retaining the original input while the
/// transcript is full. Nested commands finish before the next input line.
@MainActor
final class OutboundTextProducer {
	private let admission: TranscriptRenderAdmission
	private var producers: [() -> Bool] = []
	private var nestedInsertionIndex: Int?
	private var task: Task<Void, Never>?
	private var generation = UUID()

	init(admission: TranscriptRenderAdmission) {
		self.admission = admission
	}

	isolated deinit { task?.cancel() }

	var pendingProducerCount: Int {
		producers.count
	}

	func enqueue(_ step: @escaping () -> Bool) {
		if let index = nestedInsertionIndex {
			producers.insert(step, at: index)
			nestedInsertionIndex = index + 1
			return
		}
		producers.append(step)
		guard task == nil else { return }
		drain()
	}

	func cancel() {
		generation = UUID()
		task?.cancel()
		task = nil
		producers.removeAll()
		if nestedInsertionIndex != nil {
			nestedInsertionIndex = 0
		}
	}

	private func drain() {
		let admittedGeneration = generation
		var steps = 0
		while !producers.isEmpty, admission.hasCapacity, steps < 64 {
			let step = producers.removeFirst()
			nestedInsertionIndex = 0
			let hasMore = step()
			if hasMore, generation == admittedGeneration {
				producers.insert(step, at: nestedInsertionIndex ?? 0)
			}
			nestedInsertionIndex = nil
			guard generation == admittedGeneration else {
				if !producers.isEmpty {
					drain()
				}
				return
			}
			steps += 1
		}
		guard !producers.isEmpty else { return }
		let admission = admission
		task = Task { [weak self] in
			await Task.yield()
			await admission.waitForCapacity()
			guard !Task.isCancelled, let self, generation == admittedGeneration else { return }
			task = nil
			drain()
		}
	}
}

/// Splits only the next source line and formats only the next wire chunk.
/// AppKit text stays on the main actor with its producer.
struct OutboundTextCursor {
	private var lines: OutboundInputCursor
	private var line: LineCursor?

	init(_ text: NSAttributedString) {
		lines = OutboundInputCursor(text)
	}

	mutating func next(for target: String, on client: Client, as type: LogLineType) -> String? {
		while true {
			if let result = line?.nextLine(forChannel: target, on: client, with: type) {
				return result
			}
			guard let source = lines.next() else { return nil }
			line = LineCursor(source)
		}
	}
}

/// Retains one immutable source instead of a substring for every pasted line.
struct OutboundInputCursor {
	private let text: NSAttributedString
	private var offset = 0

	init(_ text: NSAttributedString) {
		self.text = NSAttributedString(attributedString: text)
	}

	mutating func next() -> NSAttributedString? {
		guard offset < text.length else { return nil }
		let source = text.string as NSString
		let newline = source.rangeOfCharacter(from: .newlines, range: NSRange(location: offset, length: source.length - offset))
		let end = newline.location == NSNotFound ? source.length : newline.location
		let line = text.attributedSubstring(from: NSRange(location: offset, length: end - offset))
		offset = newline.location == NSNotFound ? source.length : NSMaxRange(newline)
		return line
	}
}

extension Client {
	/// The session and target identities are checked again after any capacity
	/// wait, before a queued command can affect a replacement connection.
	func enqueueOutboundText(channels: [Channel] = [], _ step: @escaping (Client) -> Bool) {
		let session = startup.identifier
		let connection = socket?.uniqueIdentifier
		let destinations = channels.map { (channel: $0, name: $0.name) }
		if outboundTextProducer == nil {
			outboundTextProducer = OutboundTextProducer(admission: renderAdmission)
		}
		outboundTextProducer?.enqueue { [weak self] in
			guard let self, !isTerminating, startup.identifier == session, socket?.uniqueIdentifier == connection,
			      destinations.allSatisfy({ destination in
			      	destination.channel.name == destination.name && channelList.contains { $0 === destination.channel }
			      }) else { return false }
			return step(self)
		}
	}
}
