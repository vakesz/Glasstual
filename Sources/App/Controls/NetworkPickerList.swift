// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// What the network list can have selected: one of the bundled networks, keyed
/// by its own name, or the custom server the last row offers.
enum NetworkPickerSelection: Hashable {
	case network(String)
	case customServer
}

/// One row of the network list. The last row stands for a server the bundled
/// catalog does not list, which is why the network is optional.
struct NetworkPickerOption: Identifiable {
	let network: Network?

	var id: NetworkPickerSelection {
		network.map { .network($0.networkName.lowercased()) } ?? .customServer
	}

	var title: String {
		network?.networkName ?? String(localized: .NetworkPicker.customServer)
	}

	var subtitle: String {
		network?.networkDescription ?? String(localized: .NetworkPicker.connectToAnyIrcServer)
	}

	var isSecure: Bool {
		network?.prefersSecuredConnection ?? false
	}
}

/** Which of the bundled networks is chosen, and what the list offers.

 Onboarding and the connection sheet's template step show the same list over the
 same catalog; what they do with the answer is their own. Whoever owns the step
 holds one of these and reads `selectedNetwork` or `selection` off it. */
@Observable
final class NetworkPickerListModel {
	let networkList: NetworkList
	var query = ""

	var selection: NetworkPickerSelection? {
		didSet {
			if selection != oldValue {
				selectionDidChange?()
			}
		}
	}

	/** Called when a different row is chosen, for an owner that has state to
	 refill from it.

	 The onboarding step replaces the connection details it is collecting; the
	 template step reads the network when Continue is pressed and has nothing to
	 do here. */
	var selectionDidChange: (() -> Void)?

	init(networkList: NetworkList = NetworkList()) {
		self.networkList = networkList
	}

	var selectedNetwork: Network? {
		guard case let .network(name) = selection else { return nil }
		return networkList.network(named: name)
	}

	var hasSelection: Bool {
		selection == .customServer || selectedNetwork != nil
	}

	/// The title of the chosen row, the custom server row included.
	var selectedTitle: String {
		selectedNetwork?.networkName ?? String(localized: .NetworkPicker.customServer)
	}

	var popularOptions: [NetworkPickerOption] {
		guard normalizedQuery.isEmpty else { return [] }
		return networkList.popularNetworks.map { NetworkPickerOption(network: $0) }
	}

	var remainingOptions: [NetworkPickerOption] {
		let candidates = normalizedQuery.isEmpty
			? networkList.networksBelowThePopularOnes
			: networkList.listOfNetworks.filter(matchesQuery)
		return candidates.map { NetworkPickerOption(network: $0) }
	}

	var customOption: NetworkPickerOption {
		NetworkPickerOption(network: nil)
	}

	/// The custom server row always matches, so an empty result is only ever a
	/// search that found no network.
	var hasNoSearchResults: Bool {
		normalizedQuery.isEmpty == false && remainingOptions.isEmpty
	}

	private var normalizedQuery: String {
		query.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func matchesQuery(_ network: Network) -> Bool {
		let query = normalizedQuery
		return network.networkName.localizedCaseInsensitiveContains(query)
			|| network.serverAddress.localizedCaseInsensitiveContains(query)
			|| network.networkDescription.localizedCaseInsensitiveContains(query)
	}
}

extension NetworkList {
	/// The catalog with the popular networks taken out, so a list that leads
	/// with them does not name any of them twice.
	var networksBelowThePopularOnes: [Network] {
		let popularNames = Set(popularNetworks.map { $0.networkName.lowercased() })

		return listOfNetworks.filter { popularNames.contains($0.networkName.lowercased()) == false }
	}
}

/** The searchable list of bundled networks, with the custom server row last.

 The onboarding step and the connection sheet's template step both show it:
 one goes on to ask for an account, the other opens the full connection form.
 Double-clicking a row selects it and confirms in one go. */
struct NetworkPickerListView: View {
	@Bindable var model: NetworkPickerListModel
	let confirm: () -> Void

	/// `searchable` needs a navigation container to place its field in, and the
	/// list is the only part of the step that is searched.
	var body: some View {
		NavigationStack {
			List(selection: $model.selection) {
				if model.popularOptions.isEmpty == false {
					Section(.NetworkPicker.popular) {
						ForEach(model.popularOptions) { option in
							networkRow(option).tag(option.id)
						}
					}
				}

				/* The unavailable view stands in for the networks the search did
				 not match, rather than overlaying the whole list: the custom
				 server is always an answer, and an overlay covered the row that
				 offers it. */
				if model.hasNoSearchResults {
					ContentUnavailableView.search(text: model.query)
						.listRowSeparator(.hidden)
						.selectionDisabled()
				} else {
					Section(.NetworkPicker.allNetworks) {
						ForEach(model.remainingOptions) { option in
							networkRow(option).tag(option.id)
						}
					}
				}

				Section {
					networkRow(model.customOption).tag(model.customOption.id)
				}
			}
			.listStyle(.inset)
			.accessibilityIdentifier("network-picker-list")
			.accessibilityLabel(.NetworkPicker.networks)
			.searchable(text: $model.query, prompt: Text(.NetworkPicker.searchNetworks))
		}
	}

	private func networkRow(_ option: NetworkPickerOption) -> some View {
		HStack(spacing: UISpacing.regular) {
			VStack(alignment: .leading, spacing: 1) {
				Text(verbatim: option.title).lineLimit(1)
				Text(verbatim: option.subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 0)
			if option.isSecure {
				Image(systemName: "lock.fill")
					.foregroundStyle(.secondary)
					.accessibilityLabel(.NetworkPicker.secureConnection)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture(count: 2) {
			model.selection = option.id
			confirm()
		}
	}
}
