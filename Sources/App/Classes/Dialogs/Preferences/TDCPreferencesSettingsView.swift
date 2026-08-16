/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *********************************************************************** */

import AppKit
import Observation
import SwiftUI

/* Group identifiers are a contract with TDCPreferencesController.m, which
 stamps them onto every entry it returns from -settingsSidebarCatalog. */
private enum SettingsGroup: String {
	case main
	case addons
	case advanced
}

private let settingsTable = "TDCPreferencesController"

private let settingsSidebarWidth: CGFloat = 215

private let settingsFallbackPaneID = "general"

/* One bridge per TDCPreferencesController, owned by it. The navigation state
 held here used to live on a process-wide singleton. The controller is built
 fresh every time the window opens, so each reopen left another root view
 observing that one object: a single selection change then invalidated every
 root view the process had ever created instead of only the live one. */
@objc(TDCPreferencesSettingsBridge)
@MainActor
final class PreferencesSettingsBridge: NSObject {
	private let navigation = SettingsNavigation()

	@objc func selectPane(_ identifier: String) {
		navigation.select(identifier)
	}

	@objc(makeViewControllerWithController:)
	func makeViewController(with controller: TDCPreferencesController) -> NSViewController {
		/* The catalog is resolved here, on the AppKit side, and handed to the
		 view as plain data. It used to be rebuilt from `body`, which meant
		 walking the plug-in list and localising a title per row every time
		 anything at all invalidated the view. */
		let panes = controller.settingsSidebarCatalog().compactMap(SettingsPane.init(catalogEntry:))

		navigation.setAvailablePanes(panes.map(\.id))

		let rootView = SettingsRootView(
			panes: panes,
			paneProvider: SettingsPaneProvider(controller: controller),
			navigation: navigation)

		let hostingController = NSHostingController(rootView: rootView)

		hostingController.sizingOptions = []

		return hostingController
	}
}

/* Observation rather than ObservableObject, and that choice is load-bearing.
 SwiftUI's List coordinator writes its selection binding back from inside its
 own update group -- outlineViewSelectionDidChange -> withSelectionUpdateGuard
 -> UpdateGroup.ensure -> Binding.set. Behind @Published that write calls
 ObservableObjectPublisher.send() while an update is already running, which is
 exactly what "Publishing changes from within view updates" reports, and the
 re-entrant invalidation it causes is what walked the stack off its end. No
 guard on this side can prevent it: the write originates inside SwiftUI. @Observable
 has no Combine publisher to send, and folds the change into the next update
 pass instead of re-entering the current one. */
@Observable
@MainActor
private final class SettingsNavigation {
	private(set) var selectedID = settingsFallbackPaneID

	@ObservationIgnored private var availablePaneIDs: Set<String> = []

	/* Called from -installSettingsSidebar before the hosting controller exists,
	 so this is the one write that cannot land inside a view update. */
	func setAvailablePanes(_ identifiers: [String]) {
		availablePaneIDs = Set(identifiers)

		if availablePaneIDs.contains(selectedID) {
			return
		}

		selectedID = identifiers.first ?? settingsFallbackPaneID
	}

	/* Every other write funnels through here, including the ones List makes on
	 its own. A selection that is unchanged, or that names a pane the sidebar is
	 not showing, is dropped rather than applied: a redundant write still costs
	 an invalidation, and one that names a missing pane would leave the sidebar
	 and the detail view disagreeing about what is selected. */
	func select(_ identifier: String) {
		if identifier == selectedID {
			return
		}

		if availablePaneIDs.contains(identifier) == false {
			return
		}

		selectedID = identifier
	}

	/* Handed to List in place of a projected binding so that writes coming back
	 out of the selection machinery are filtered too. Selection can therefore
	 never name a row the sidebar is not showing, which removes the reason List
	 would want to correct the binding on its own. */
	var selection: Binding<String> {
		Binding(
			get: { self.selectedID },
			set: { self.select($0) })
	}
}

/* Resolves a pane's AppKit view on demand. The controller is held weakly on
 purpose: it owns the window, which owns the hosting controller, which owns
 this. A strong reference closes that ring and keeps every settings window
 that has ever been opened -- and its panes -- alive for the session. */
@MainActor
private struct SettingsPaneProvider {
	private weak var controller: TDCPreferencesController?

	init(controller: TDCPreferencesController) {
		self.controller = controller
	}

	func view(for identifier: String) -> NSView? {
		controller?.view(forSettingsPaneIdentifier: identifier)
	}
}

private struct SettingsPane: Identifiable, Hashable {
	let id: String
	let title: String
	let systemImage: String
	let group: SettingsGroup

	init?(catalogEntry entry: [String: String]) {
		guard
			let id = entry["id"],
			let title = entry["title"],
			let symbol = entry["symbol"],
			let group = entry["group"].flatMap(SettingsGroup.init(rawValue:))
		else {
			return nil
		}

		self.id = id
		self.title = title
		self.systemImage = symbol
		self.group = group
	}
}

private struct SettingsRootView: View {
	let panes: [SettingsPane]
	let paneProvider: SettingsPaneProvider

	/* Plain reference, no property wrapper: reading navigation.selectedID from
	 body is what registers this view with Observation. */
	let navigation: SettingsNavigation

	private var activePane: SettingsPane? {
		panes.first { $0.id == navigation.selectedID } ?? panes.first
	}

	var body: some View {
		NavigationSplitView(columnVisibility: .constant(.all)) {
			SettingsSidebarView(panes: panes, selection: navigation.selection)
				/* Pinned rather than ranged: a resizable column lets a wide
				 detail pane squeeze the sidebar, so it visibly shifts as you
				 move between panes. The frame is what actually holds when the
				 split view is hosted inside AppKit. */
			.frame(width: settingsSidebarWidth)
				.navigationSplitViewColumnWidth(settingsSidebarWidth)
				.toolbar(removing: .sidebarToggle)
		} detail: {
			if let activePane {
				SettingsDetailView(paneProvider: paneProvider, pane: activePane)
			}
		}
		.navigationSplitViewStyle(.balanced)
		.frame(minWidth: 860, minHeight: 560)
	}
}

private struct SettingsSidebarView: View {
	let panes: [SettingsPane]

	let selection: Binding<String>

	private func panes(in group: SettingsGroup) -> [SettingsPane] {
		panes.filter { $0.group == group }
	}

	var body: some View {
		List(selection: selection) {
			ForEach(panes(in: .main)) { pane in
				SettingsSidebarRow(pane: pane)
			}

			let addons = panes(in: .addons)

			if addons.isEmpty == false {
				Section(LocalizedKey("\(settingsTable)[sb-gr-ad]")) {
					ForEach(addons) { pane in
						SettingsSidebarRow(pane: pane)
					}
				}
			}

			let advanced = panes(in: .advanced)

			if advanced.isEmpty == false {
				Section(LocalizedKey("\(settingsTable)[sb-gr-av]")) {
					ForEach(advanced) { pane in
						SettingsSidebarRow(pane: pane)
					}
				}
			}
		}
		.listStyle(.sidebar)
		.scrollEdgeEffectStyle(.soft, for: .all)
		.navigationTitle(LocalizedKey("\(settingsTable)[sb-tt]"))
		.safeAreaInset(edge: .bottom, spacing: 0) {
			SettingsVersionFooter()
		}
	}
}

private struct SettingsSidebarRow: View {
	let pane: SettingsPane

	var body: some View {
		Label(pane.title, systemImage: pane.systemImage)
			.tag(pane.id)
	}
}

private struct SettingsVersionFooter: View {
	private var versionText: String {
		let info = Bundle.main.infoDictionary

		let version = info?["CFBundleShortVersionString"] as? String ?? ""
		let build = info?["CFBundleVersion"] as? String ?? ""

		return LocalizedKey("\(settingsTable)[sb-vers]", version, build)
	}

	var body: some View {
		VStack(spacing: 0) {
			Divider()

			Text(versionText)
				.font(.footnote)
				.foregroundStyle(.tertiary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 14)
				.padding(.vertical, 8)
		}
		/* Opaque so that list rows scroll behind it rather than through it. */
		.background(.bar)
		.accessibilityLabel(versionText)
	}
}

private struct SettingsDetailView: View {
	let paneProvider: SettingsPaneProvider
	let pane: SettingsPane

	var body: some View {
		ScrollView(.vertical) {
			if let view = paneProvider.view(for: pane.id) {
				AppKitPreferencePane(view: view)
					.padding(20)
			}
		}
		.scrollEdgeEffectStyle(.soft, for: .all)
		.navigationTitle(pane.title)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}

/* The settings panes are still laid out in TDCPreferences.xib. Each one is
 hosted here as-is rather than being wrapped in a Form: the panes carry their
 own label column and spacing, and a grouped Form would draw a second set of
 insets and card chrome around them. */
private struct AppKitPreferencePane: NSViewRepresentable {
	let view: NSView

	func makeNSView(context: Context) -> NSView {
		NSView()
	}

	func updateNSView(_ container: NSView, context: Context) {
		if view.superview === container {
			return
		}

		for subview in container.subviews {
			subview.removeFromSuperview()
		}

		view.removeFromSuperview()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.prefersCompactControlSizeMetrics = true

		container.addSubview(view)

		/* The bottom edge is an inequality, not a pin. Pinning it makes the
		 container's height and the pane's height define one another, and
		 -sizeThatFits handing -fittingSize straight back to SwiftUI closes the
		 ring: the pane is sized from a container that was sized from the pane.
		 Letting the container be taller than its content keeps height flowing
		 one way, out of the pane and into the layout. */
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			view.topAnchor.constraint(equalTo: container.topAnchor),
			container.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor),
		])
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
		let fitting = view.fittingSize

		/* Never report back less than the pane needs. The panes are laid out at
		 a fixed width in the XIB, so a narrower proposal clips controls rather
		 than reflowing them. The window's own 860pt minimum keeps this from
		 biting in practice. */
		return CGSize(
			width: max(proposal.width ?? fitting.width, fitting.width),
			height: fitting.height)
	}
}
