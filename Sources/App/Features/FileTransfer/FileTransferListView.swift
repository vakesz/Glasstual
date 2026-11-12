// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FileTransferListView: View {
	let center: FileTransferStore
	@Bindable private var model: FileTransferList
	/// Quick Look binds straight into the access the window is holding, so the
	/// list model is not asked to forward a preview selection it does not own.
	@Bindable private var fileAccess: FileTransferFileAccess

	init(center: FileTransferStore) {
		self.center = center
		model = center.model
		fileAccess = center.model.fileAccess
	}

	/** Which directions the window was last showing.

	 The model stays the authority — a notification action can widen the filter
	 to reveal the transfer it names — so this only remembers what the model was
	 last set to, and restores it when the window comes back. */
	@SceneStorage("file-transfer-filter") private var storedDirectionFilter = FileTransferDirectionFilter.all

	var body: some View {
		List(selection: $model.selection) {
			if model.xdccRequests.isEmpty {
				transferRows
			} else {
				Section {
					ForEach(model.xdccRequests) { pending in
						XDCCRequestRow(pending: pending) { center.cancelXDCCRequest(pending) }
							.selectionDisabled()
					}
				} header: {
					Text(.FileTransfer.waitingForBots)
				}
				Section {
					transferRows
				} header: {
					Text(.FileTransfer.transfersSection)
				}
			}
		}
		.listStyle(.inset)
		.alternatingRowBackgrounds(model.visibleTransfers.isEmpty ? .disabled : .enabled)
		.accessibilityLabel(Text(.FileTransfer.fileTransfers))
		.overlay {
			if model.visibleTransfers.isEmpty, model.xdccRequests.isEmpty {
				ContentUnavailableView {
					Label(.FileTransfer.noFileTransfers, systemImage: "arrow.left.arrow.right")
				} description: {
					Text(.FileTransfer.transfersAppearHere)
				}
			}
		}
		.onChange(of: model.selection) { model.selectionDidChange() }
		.onChange(of: model.filter) { storedDirectionFilter = model.filter }
		.onKeyPress(.space) {
			guard model.canPerform(.preview) else { return .ignored }
			center.perform(.preview, on: model.selection)
			return .handled
		}
		.onDeleteCommand(perform: model.selection.isEmpty ? nil : { center.perform(.remove, on: model.selection) })
		.navigationSubtitle(Text(.FileTransfer.transfers(model.visibleTransfers.count)))
		.toolbar {
			ToolbarItem(placement: .principal) {
				Picker(.FileTransfer.show, selection: $model.filter) {
					Text(.FileTransfer.all).tag(FileTransferDirectionFilter.all)
					Text(.FileTransfer.sending).tag(FileTransferDirectionFilter.sending)
					Text(.FileTransfer.receiving).tag(FileTransferDirectionFilter.receiving)
				}
				.pickerStyle(.segmented)
				.fixedSize()
			}

			/* Start and Stop hold their place while the direction filter and the
			 title share a narrow window; the other commands overflow first. */
			if #available(macOS 26.1, *) {
				ToolbarItemGroup(placement: .primaryAction) {
					toolbarButtons(keepingPlace: true)
				}
				.visibilityPriority(.high)
			} else {
				ToolbarItemGroup(placement: .primaryAction) {
					toolbarButtons(keepingPlace: true)
				}
			}

			ToolbarItemGroup(placement: .primaryAction) {
				toolbarButtons(keepingPlace: false)
			}

			ToolbarSpacer(placement: .primaryAction)

			ToolbarItem(placement: .primaryAction) {
				Button(action: center.clearStoppedTransfers) {
					Label(.FileTransfer.clearAllStoppedTransfers, systemImage: "xmark.bin")
				}
				.help(Text(.FileTransfer.clearAllStoppedTransfers))
				.disabled(model.canClearStoppedTransfers == false)
			}
		}
		.task { model.activate(restoring: storedDirectionFilter) }
		.onExitCommand(perform: center.dismiss)
		.quickLookPreview($fileAccess.previewSelection, in: model.previewItems)
		.onDisappear {
			fileAccess.previewSelection = nil
			fileAccess.releaseShareAccess()
		}
		.fileImporter(
			isPresented: $model.isChoosingDestination,
			allowedContentTypes: [.folder],
			onCompletion: center.completeDestinationSelection
		)
	}

	private func toolbarButtons(keepingPlace: Bool) -> some View {
		ForEach(FileTransferAction.toolbarCommands.filter { $0.keepsToolbarPlace == keepingPlace }, id: \.self) { action in
			toolbarButton(for: action)
		}
	}

	@ViewBuilder
	private func toolbarButton(for action: FileTransferAction) -> some View {
		switch action {
		case .start:
			Button {
				center.perform(.start, on: model.selection)
			} label: {
				Label(model.startActionTitle(), systemImage: "play.circle")
			}
			.help(model.startActionTitle())
			.disabled(model.canPerform(.start) == false)
			.accessibilityIdentifier(AccessibilityIdentifier.fileTransfersStart)
		case .stop:
			Button {
				center.perform(.stop, on: model.selection)
			} label: {
				Label(.FileTransfer.cancelTransfer, systemImage: "stop.circle")
			}
			.help(Text(.FileTransfer.cancelTransfer))
			.disabled(model.canPerform(.stop) == false)
			.accessibilityIdentifier(AccessibilityIdentifier.fileTransfersStop)
		case .downloadTo:
			Button {
				center.perform(.downloadTo, on: model.selection)
			} label: {
				Label(.FileTransfer.downloadTo, systemImage: "square.and.arrow.down")
			}
			.help(Text(.FileTransfer.downloadTo))
			.disabled(model.canPerform(.downloadTo) == false)
		case .preview:
			Button {
				center.perform(.preview, on: model.selection)
			} label: {
				Label(.FileTransfer.quickLook, systemImage: "eye")
			}
			.help(Text(.FileTransfer.quickLook))
			.disabled(model.canPerform(.preview) == false)
		case .showCertificate:
			Button {
				center.perform(.showCertificate, on: model.selection)
			} label: {
				Label(.FileTransfer.showCertificate, systemImage: "checkmark.seal")
			}
			.help(Text(.FileTransfer.showCertificate))
			.disabled(model.canPerform(.showCertificate) == false)
			.accessibilityIdentifier("file-transfer-show-certificate")
		case .remove, .open, .reveal:
			EmptyView()
		}
	}

	private var transferRows: some View {
		ForEach(model.visibleTransfers, id: \.uniqueIdentifier) { transfer in
			row(for: transfer)
		}
	}

	/// A finished transfer's file can be dragged out of the window. The check is
	/// on the status first: asking for the URL costs a security-scope round trip
	/// and a `stat`, which a row that is still moving bytes redraws too often to
	/// be worth paying.
	@ViewBuilder
	private func row(for transfer: FileTransfer) -> some View {
		let identifiers = model.contextSelection(for: transfer.uniqueIdentifier)
		let content = FileTransferRowView(transfer: transfer)
			.tag(transfer.uniqueIdentifier)
			.contextMenu { transferMenu(for: identifiers) }
			/* Opening on a double click is what a row of finished downloads is
			 for; a simultaneous gesture leaves the single click selecting. */
			.simultaneousGesture(TapGesture(count: 2).onEnded {
				guard model.canPerform(.open, on: identifiers) else { return }
				center.perform(.open, on: identifiers)
			})

		if transfer.transferStatus == .complete,
		   let fileURL = model.selectedFileURLs(for: [transfer.uniqueIdentifier]).first
		{
			content.draggable(fileURL) {
				Text(verbatim: transfer.filename)
			}
		} else {
			content
		}
	}

	/// Unavailable commands are left out, not dimmed, as context menus do.
	@ViewBuilder
	private func transferMenu(for identifiers: Set<String>) -> some View {
		if model.canPerform(.start, on: identifiers) {
			Button(model.startActionTitle(for: identifiers)) { center.perform(.start, on: identifiers) }
		}
		if model.canPerform(.downloadTo, on: identifiers) {
			Button(.FileTransfer.downloadTo) { center.perform(.downloadTo, on: identifiers) }
		}
		if model.canPerform(.stop, on: identifiers) {
			Button(.FileTransfer.cancelTransfer) { center.perform(.stop, on: identifiers) }
		}

		Divider()
		if model.canPerform(.preview, on: identifiers) {
			Button(.FileTransfer.quickLook) { center.perform(.preview, on: identifiers) }
		}
		if model.canPerform(.open, on: identifiers) {
			Button(.FileTransfer.openFile) { center.perform(.open, on: identifiers) }
		}
		if model.canPerform(.reveal, on: identifiers) {
			Button(.FileTransfer.showInFinder) { center.perform(.reveal, on: identifiers) }
		}
		if model.canPerform(.showCertificate, on: identifiers) {
			Button(.FileTransfer.showCertificate) { center.perform(.showCertificate, on: identifiers) }
		}

		/* Asking the model settles the rows' local files once for the whole
		 menu, and leaves the share holding the access it needs to read them. */
		let urls = model.shareableFileURLs(for: identifiers)
		if urls.isEmpty == false, urls.count == identifiers.count {
			ShareLink(items: urls) {
				Text(.FileTransfer.share)
			}
		}

		Divider()
		Button(.FileTransfer.removeFromList, role: .destructive) {
			center.perform(.remove, on: identifiers)
		}
	}
}

private struct FileTransferRowView: View {
	let transfer: FileTransfer

	var body: some View {
		let presentation = FileTransferRowPresentation(transfer: transfer)

		HStack(spacing: UISpacing.wide) {
			FileTransferIconView(filename: transfer.filename)
				.equatable()

			VStack(alignment: .leading, spacing: UISpacing.tight) {
				HStack {
					if let security = presentation.security {
						Image(systemName: security.indicator.symbolName)
							.symbolRenderingMode(security.indicator == .unverified ? .multicolor : .monochrome)
							.foregroundStyle(.secondary)
							.help(Text(verbatim: security.details))
							.accessibilityLabel(Text(verbatim: security.accessibilityLabel))
							.accessibilityIdentifier("file-transfer-security-\(transfer.uniqueIdentifier)")
					}
					Text(verbatim: presentation.filename)
						.lineLimit(1)
						.accessibilityIdentifier("file-transfer-filename-\(transfer.uniqueIdentifier)")
					if let requested = presentation.requestedBadge {
						Text(verbatim: requested)
							.font(.caption)
							.foregroundStyle(.secondary)
							.accessibilityIdentifier("file-transfer-requested-\(transfer.uniqueIdentifier)")
					}
					Spacer()
					Text(verbatim: presentation.totalSize)
						.font(.caption)
						.foregroundStyle(.secondary)
						.monospacedDigit()
						.accessibilityIdentifier("file-transfer-bytes-\(transfer.uniqueIdentifier)")
						.accessibilityLabel(Text(.FileTransfer.transferTotalSize(presentation.totalSize)))
						.accessibilityValue(Text(verbatim: presentation.processedSize))
				}

				progressView(presentation.progress)

				Text(verbatim: presentation.status)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.accessibilityIdentifier("file-transfer-status-\(transfer.uniqueIdentifier)")
			}
		}
		.padding(.vertical, UISpacing.tight)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("file-transfer-row-\(transfer.uniqueIdentifier)")
	}

	@ViewBuilder
	private func progressView(_ progress: FileTransferRowPresentation.Progress) -> some View {
		switch progress {
		case .hidden:
			EmptyView()
		case .indeterminate:
			ProgressView()
				.progressViewStyle(.linear)
				.accessibilityLabel(Text(.FileTransfer.transferProgress))
		case let .determinate(value, total):
			ProgressView(value: Double(value), total: Double(max(total, 1)))
				.progressViewStyle(.linear)
				.accessibilityLabel(Text(.FileTransfer.transferProgress))
		}
	}
}

/// A filename changes only when a download claims its destination. Keep the
/// Workspace icon lookup out of a row that redraws for every progress sample.
private struct FileTransferIconView: View, Equatable {
	let filename: String

	var body: some View {
		Image(nsImage: fileIcon)
			.resizable()
			.scaledToFit()
			.frame(width: 44, height: 44)
			.accessibilityHidden(true)
	}

	private var fileIcon: NSImage {
		let contentType = UTType(filenameExtension: (filename as NSString).pathExtension)
		return NSWorkspace.shared.icon(for: contentType ?? .data)
	}
}

struct FileTransferListScene: Scene {
	let center: FileTransferStore

	var body: some Scene {
		WindowGroup(
			String(localized: .FileTransfer.fileTransfers),
			id: ApplicationSceneID.fileTransfers,
			for: SingletonSceneValue.self
		) { _ in
			FileTransferListView(center: center)
				.accessibilityElement(children: .contain)
				.accessibilityIdentifier(AccessibilityIdentifier.fileTransfersWindow)
				.frame(
					minWidth: 620,
					idealWidth: 680,
					minHeight: 360,
					idealHeight: 440
				)
		} defaultValue: { .instance }
			.defaultSize(width: 680, height: 440)
			/* `contentSize` pins the window to its ideal size every time it opens,
			 which threw away whatever size the user had left it at. */
			.windowResizability(.contentMinSize)
	}
}
