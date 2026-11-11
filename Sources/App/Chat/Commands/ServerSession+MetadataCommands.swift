// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// What `/metadata` was asked to do.
nonisolated struct MetadataCommandRequest: Equatable {
	/// `*` for the user.
	let target: String
	let subcommand: MetadataSubcommand
	/// The keys `get`, `sub` and `unsub` name, or the one key `set` names.
	let keys: [String]
	/// The value `set` sends; `nil` removes the key.
	let value: String?

	/** Reads `/metadata [target] <subcommand> [arguments]`.

	 A first word that is a subcommand targets the user. The value of `set` is
	 the rest of the line; `""` sets the empty value, and nothing removes the
	 key. `nil` when the line names no subcommand. */
	init?(arguments: String) {
		var tokenizer = CommandTokenizer(arguments)
		let first = tokenizer.nextToken()

		if let subcommand = MetadataSubcommand(rawValue: first.lowercased()) {
			target = "*"
			self.subcommand = subcommand
		} else {
			guard first.isEmpty == false,
			      let subcommand = MetadataSubcommand(rawValue: tokenizer.nextToken().lowercased())
			else { return nil }
			target = first
			self.subcommand = subcommand
		}

		if subcommand == .set {
			let key = tokenizer.nextToken()
			let rest = String(tokenizer.remainder)
			keys = key.isEmpty ? [] : [key]
			value = rest.isEmpty ? nil : (rest == "\"\"" ? "" : rest)
		} else {
			var keys: [String] = []
			while case let key = tokenizer.nextToken(), key.isEmpty == false {
				keys.append(key)
			}
			self.keys = keys
			value = nil
		}
	}
}

extension ServerSession {
	func dispatchMetadataCommand(_ parsed: ParsedUserCommand) {
		let arguments = parsed.arguments.rest

		guard arguments.isEmpty == false else {
			printInvalidSyntaxMessage(for: parsed.command)
			printOwnProfileSummary()
			return
		}

		guard let request = MetadataCommandRequest(arguments: arguments) else {
			printInvalidSyntaxMessage(for: parsed.command)
			return
		}

		guard canSendMetadata else {
			printDebugInformation(toConsole: String(localized: .Metadata.unsupported))
			return
		}

		if let invalid = request.keys.first(where: { MetadataKey.isValid($0) == false }) {
			printDebugInformation(toConsole: String(localized: .Metadata.invalidKey(ControlCharacterDisposition.singleLine(invalid))))
			return
		}

		perform(request, command: parsed.command)
	}

	private func perform(_ request: MetadataCommandRequest, command: String) {
		let isOwn = metadataTargetKey(request.target) == "*"

		switch request.subcommand {
		case .get, .sub, .unsub:
			guard request.keys.isEmpty == false else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			if request.subcommand == .sub, let maximum = metadataValues.maximumSubscriptions,
			   metadata.subscribed.union(request.keys).count > maximum
			{
				printDebugInformation(toConsole: String(localized: .Metadata.tooManySubscriptions(maximum)))
				return
			}
			if request.subcommand == .get {
				sendMetadataQuery(.get, target: request.target, arguments: request.keys, printsOutput: true)
			} else {
				send(.metadata, arguments: ["*", request.subcommand.wireName] + request.keys)
			}
		case .list, .sync:
			sendMetadataQuery(request.subcommand, target: request.target, arguments: [], printsOutput: true)
		case .subs:
			sendMetadataQuery(.subs, target: "*", arguments: [], printsOutput: true)
		case .clear:
			if isOwn {
				clearOwnMetadata { [weak self] failure in
					self?.printDebugInformation(toConsole: failure?.localizedDescription
						?? String(localized: .Metadata.profileCleared))
				}
			} else {
				sendMetadataQuery(.clear, target: request.target, arguments: [], printsOutput: true)
			}
		case .set:
			guard let key = request.keys.first else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			if isOwn {
				setOwnMetadata(key: key, value: request.value) { [weak self] outcome in
					self?.printMetadataSetOutcome(outcome, key: key)
				}
			} else {
				sendMetadataQuery(
					.set, target: request.target, arguments: [key] + (request.value.map { [$0] } ?? []), printsOutput: true
				)
			}
		}
	}

	private func printMetadataSetOutcome(_ outcome: MetadataSetOutcome, key: String) {
		let text = switch outcome {
		case let .stored(value): Self.formattedMetadataEntry(key: key, visibility: nil, value: value)
		case let .rateLimited(retryAfter): String(localized: .Metadata.rateLimitedRetrying(retryAfter))
		case let .failed(failure): failure.localizedDescription
		}
		printDebugInformation(toConsole: text)
	}

	/// What `/metadata` alone prints after its syntax: the user's own profile.
	private func printOwnProfileSummary() {
		guard isCapabilityEnabled(.metadata) else {
			printDebugInformation(toConsole: String(localized: .Metadata.unsupported))
			return
		}

		let values = metadata.ownWireValues.filter { MetadataKey.profileKeys.contains($0.key) }
		guard values.isEmpty == false else {
			printDebugInformation(toConsole: String(localized: .Metadata.noMetadata))
			return
		}

		for key in MetadataKey.profileKeys {
			guard let value = values[key] else { continue }
			printDebugInformation(toConsole: Self.formattedMetadataEntry(key: key, visibility: nil, value: value))
		}
	}
}
