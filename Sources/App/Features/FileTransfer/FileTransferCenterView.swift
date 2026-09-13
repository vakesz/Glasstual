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

struct FileTransferCenterView: View {
	let center: FileTransferCenter
	@Bindable private var model: FileTransferCenterModel

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
				Picker(FileTransferStrings.show, selection: $model.filter) {
					Text(verbatim: FileTransferStrings.all).tag(FileTransferSelection.all)
					Text(verbatim: FileTransferStrings.sending).tag(FileTransferSelection.sending)
					Text(verbatim: FileTransferStrings.receiving).tag(FileTransferSelection.receiving)
				}
				.pickerStyle(.segmented)
				.fixedSize()

				Spacer()
				Text(verbatim: FileTransferStrings.transferCount(model.visibleTransfers.count))
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
					ContentUnavailableView(
						FileTransferStrings.noTransfers,
						systemImage: "arrow.left.arrow.right",
						description: Text(verbatim: FileTransferStrings.noTransfersDescription)
					)
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
			.accessibilityLabel(FileTransferStrings.fileTransfers)

			Divider()
			HStack(spacing: 8) {
				Button(FileTransferStrings.clearStopped, action: center.clearStoppedTransfers)
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
					Label(FileTransferStrings.cancelTransfer, systemImage: "stop.fill")
				}
				.disabled(model.canPerform(.stop) == false)

				Button {
					center.perform(.preview, on: model.selection)
				} label: {
					Label(FileTransferStrings.quickLook, systemImage: "eye")
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
	private func row(for transfer: FileTransferController) -> some View {
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
		Button(FileTransferStrings.cancelTransfer) { center.perform(.stop, on: identifiers) }
			.disabled(model.canPerform(.stop, on: identifiers) == false)

		Divider()
		Button(FileTransferStrings.quickLook) { center.perform(.preview, on: identifiers) }
			.disabled(model.canPerform(.preview, on: identifiers) == false)
		Button(FileTransferStrings.openFile) { center.perform(.open, on: identifiers) }
			.disabled(model.canPerform(.open, on: identifiers) == false)
		Button(FileTransferStrings.showInFinder) { center.perform(.reveal, on: identifiers) }
			.disabled(model.canPerform(.reveal, on: identifiers) == false)

		/* Asking the model settles the rows' local files once for the whole
		 menu, and leaves the share holding the access it needs to read them. */
		let urls = model.shareableFileURLs(for: identifiers)
		ShareLink(items: urls) {
			Text(verbatim: FileTransferStrings.share)
		}
		.disabled(urls.count != identifiers.count)

		Divider()
		Button(FileTransferStrings.removeFromList, role: .destructive) {
			center.perform(.remove, on: identifiers)
		}
	}
}

private struct FileTransferRowView: View {
	let transfer: FileTransferController

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
						.accessibilityLabel(Text(verbatim: FileTransferStrings.totalSize(presentation.totalSize)))
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
				.accessibilityLabel(FileTransferStrings.transferProgress)
		case let .determinate(value, total):
			ProgressView(value: Double(value), total: Double(max(total, 1)))
				.progressViewStyle(.linear)
				.accessibilityLabel(FileTransferStrings.transferProgress)
		}
	}

	private var fileIcon: NSImage {
		let contentType = UTType(filenameExtension: (transfer.filename as NSString).pathExtension)
		return NSWorkspace.shared.icon(for: contentType ?? .data)
	}
}
