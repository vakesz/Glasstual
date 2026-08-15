/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *********************************************************************** */

import AppKit
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

@objc(TDCPreferencesSettingsBridge)
final class PreferencesSettingsBridge: NSObject {
	@objc static func selectPane(_ identifier: String) {
		SettingsNavigation.shared.selectedID = identifier
	}

	@objc(makeViewControllerWithController:)
	static func makeViewController(with controller: TDCPreferencesController) -> NSViewController {
		let hostingController = NSHostingController(rootView: SettingsRootView(controller: controller))

		hostingController.sizingOptions = []

		return hostingController
	}
}

private final class SettingsNavigation: ObservableObject {
	static let shared = SettingsNavigation()

	@Published var selectedID = "general"

	private init() {}
}

private struct SettingsPane: Identifiable, Hashable {
	let id: String
	let title: String
	let systemImage: String
	let group: SettingsGroup
}

private struct SettingsRootView: View {
	let controller: TDCPreferencesController

	@ObservedObject private var navigation = SettingsNavigation.shared

	private var panes: [SettingsPane] {
		controller.settingsSidebarCatalog().compactMap { item in
			guard
				let id = item["id"],
				let title = item["title"],
				let symbol = item["symbol"],
				let group = item["group"].flatMap(SettingsGroup.init(rawValue:))
			else {
				return nil
			}

			return SettingsPane(id: id, title: title, systemImage: symbol, group: group)
		}
	}

	private var activePane: SettingsPane? {
		let panes = self.panes

		return panes.first { $0.id == navigation.selectedID } ?? panes.first
	}

	var body: some View {
		NavigationSplitView(columnVisibility: .constant(.all)) {
			SettingsSidebarView(panes: panes, selectedID: $navigation.selectedID)
				/* Pinned rather than ranged: a resizable column lets a wide
				 detail pane squeeze the sidebar, so it visibly shifts as you
				 move between panes. The frame is what actually holds when the
				 split view is hosted inside AppKit. */
				.frame(width: settingsSidebarWidth)
				.navigationSplitViewColumnWidth(settingsSidebarWidth)
				.toolbar(removing: .sidebarToggle)
		} detail: {
			if let activePane {
				SettingsDetailView(controller: controller, pane: activePane)
			}
		}
		.navigationSplitViewStyle(.balanced)
		.frame(minWidth: 860, minHeight: 560)
		.onAppear {
			let panes = self.panes

			if panes.contains(where: { $0.id == navigation.selectedID }) == false {
				navigation.selectedID = panes.first?.id ?? "general"
			}
		}
	}
}

private struct SettingsSidebarView: View {
	let panes: [SettingsPane]

	@Binding var selectedID: String

	private func panes(in group: SettingsGroup) -> [SettingsPane] {
		panes.filter { $0.group == group }
	}

	var body: some View {
		List(selection: $selectedID) {
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
	let controller: TDCPreferencesController
	let pane: SettingsPane

	var body: some View {
		ScrollView(.vertical) {
			if let view = controller.view(forSettingsPaneIdentifier: pane.id) {
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

		container.subviews.forEach { $0.removeFromSuperview() }

		view.removeFromSuperview()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.prefersCompactControlSizeMetrics = true

		container.addSubview(view)

		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			view.topAnchor.constraint(equalTo: container.topAnchor),
			view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
		])
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
		let fitting = view.fittingSize

		return CGSize(width: proposal.width ?? fitting.width, height: fitting.height)
	}
}
