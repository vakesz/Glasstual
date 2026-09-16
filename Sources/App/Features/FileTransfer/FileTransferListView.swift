/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FileTransferListView: View {
	let center: FileTransferCenter
	@Bindable private var model: FileTransferList

	init(center: FileTransferCenter) {
		self.center = center
		model = center.model
	}

	/** Which directions the window was last showing.

	 The model stays the authority — a notification action can widen the filter
	 to reveal the transfer it names — so this only remembers what the model was
	 last set to, and restores it when the window comes back. */
	@SceneStorage("file-transfer-filter") private var shownDirections = FileTransferSelection.all

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Picker(.FileTransfers.show, selection: $model.filter) {
					Text(.FileTransfers.all).tag(FileTransferSelection.all)
					Text(.FileTransfers.sending).tag(FileTransferSelection.sending)
					Text(.FileTransfers.receiving).tag(FileTransferSelection.receiving)
				}
				.pickerStyle(.segmented)
				.fixedSize()

				Spacer()
				Text(.FileTransfers.transfers(model.visibleTransfers.count))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)

			List(selection: $model.selection) {
				ForEach(model.visibleTransfers, id: \.uniqueIdentifier) { transfer in
					row(for: transfer)
				}
			}
			.listStyle(.inset(alternatesRowBackgrounds: true))
			.overlay {
				if model.visibleTransfers.isEmpty {
					ContentUnavailableView {
						Label(.FileTransfers.noFileTransfers, systemImage: "arrow.left.arrow.right")
					} description: {
						Text(.FileTransfers.transfersAppearHere)
					}
				}
			}
			.onChange(of: model.selection) { model.selectionDidChange() }
			.onChange(of: model.filter) { shownDirections = model.filter }
			.onKeyPress(.space) {
				guard model.canPerform(.preview) else { return .ignored }
				center.perform(.preview, on: model.selection)
				return .handled
			}
			.onDeleteCommand(perform: model.selection.isEmpty ? nil : { center.perform(.remove, on: model.selection) })
			.accessibilityLabel(Text(.FileTransfers.fileTransfers))

			Divider()
			HStack(spacing: 8) {
				Button(.FileTransfers.clearAllStoppedTransfers, action: center.clearStoppedTransfers)
					.disabled(model.canClearStoppedTransfers == false)

				Spacer()

				Button {
					center.perform(.start, on: model.selection)
				} label: {
					Label(model.startActionTitle(), systemImage: "play.fill")
				}
				.disabled(model.canPerform(.start) == false)

				Button {
					center.perform(.stop, on: model.selection)
				} label: {
					Label(.FileTransfers.cancelTransfer, systemImage: "stop.fill")
				}
				.disabled(model.canPerform(.stop) == false)

				Button {
					center.perform(.preview, on: model.selection)
				} label: {
					Label(.FileTransfers.quickLook, systemImage: "eye")
				}
				.disabled(model.canPerform(.preview) == false)
			}
			.controlSize(.small)
			.padding(10)
		}
		.task { model.filter = shownDirections }
		.onExitCommand(perform: center.dismiss)
		.quickLookPreview($model.previewSelection, in: model.previewItems)
		.onDisappear {
			model.previewSelection = nil
			model.releaseShareAccess()
		}
		.fileImporter(
			isPresented: $model.isChoosingDestination,
			allowedContentTypes: [.folder],
			onCompletion: center.completeDestinationSelection
		)
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

	@ViewBuilder
	private func transferMenu(for identifiers: Set<String>) -> some View {
		Button(model.startActionTitle(for: identifiers)) { center.perform(.start, on: identifiers) }
			.disabled(model.canPerform(.start, on: identifiers) == false)
		Button(.FileTransfers.cancelTransfer) { center.perform(.stop, on: identifiers) }
			.disabled(model.canPerform(.stop, on: identifiers) == false)

		Divider()
		Button(.FileTransfers.quickLook) { center.perform(.preview, on: identifiers) }
			.disabled(model.canPerform(.preview, on: identifiers) == false)
		Button(.FileTransfers.openFile) { center.perform(.open, on: identifiers) }
			.disabled(model.canPerform(.open, on: identifiers) == false)
		Button(.FileTransfers.showInFinder) { center.perform(.reveal, on: identifiers) }
			.disabled(model.canPerform(.reveal, on: identifiers) == false)

		/* Asking the model settles the rows' local files once for the whole
		 menu, and leaves the share holding the access it needs to read them. */
		let urls = model.shareableFileURLs(for: identifiers)
		ShareLink(items: urls) {
			Text(.FileTransfers.share)
		}
		.disabled(urls.count != identifiers.count)

		Divider()
		Button(.FileTransfers.removeFromList, role: .destructive) {
			center.perform(.remove, on: identifiers)
		}
	}
}

private struct FileTransferRowView: View {
	let transfer: FileTransfer

	var body: some View {
		let presentation = FileTransferRowPresentation(transfer: transfer)

		HStack(spacing: 12) {
			Image(nsImage: fileIcon)
				.resizable()
				.scaledToFit()
				.frame(width: 44, height: 44)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 5) {
				HStack {
					Text(verbatim: presentation.filename)
						.lineLimit(1)
						.accessibilityIdentifier("file-transfer-filename-\(transfer.uniqueIdentifier)")
					Spacer()
					Text(verbatim: presentation.totalSize)
						.font(.caption)
						.foregroundStyle(.secondary)
						.monospacedDigit()
						.accessibilityIdentifier("file-transfer-bytes-\(transfer.uniqueIdentifier)")
						.accessibilityLabel(Text(.FileTransfers.transferTotalSize(presentation.totalSize)))
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
		.padding(.vertical, 5)
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
				.accessibilityLabel(Text(.FileTransfers.transferProgress))
		case let .determinate(value, total):
			ProgressView(value: Double(value), total: Double(max(total, 1)))
				.progressViewStyle(.linear)
				.accessibilityLabel(Text(.FileTransfers.transferProgress))
		}
	}

	private var fileIcon: NSImage {
		let contentType = UTType(filenameExtension: (transfer.filename as NSString).pathExtension)
		return NSWorkspace.shared.icon(for: contentType ?? .data)
	}
}

struct FileTransferListScene: Scene {
	let center: FileTransferCenter

	var body: some Scene {
		Window(String(localized: .FileTransfers.fileTransfers), id: ApplicationSceneID.fileTransfers) {
			FileTransferListView(center: center)
				.frame(
					minWidth: 620,
					idealWidth: 680,
					minHeight: 360,
					idealHeight: 440
				)
		}
		.defaultSize(width: 680, height: 440)
		/* `contentSize` pins the window to its ideal size every time it opens,
		 which threw away whatever size the user had left it at. */
		.windowResizability(.contentMinSize)
	}
}
