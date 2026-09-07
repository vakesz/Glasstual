/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
	@Bindable var model: FileTransferCenterModel
	let perform: (FileTransferAction, Set<String>) -> Void
	let clearStopped: () -> Void
	let close: () -> Void
	let chooseDestination: (Result<URL, Error>) -> Void

	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Picker(FileTransferStrings.show, selection: $model.filter) {
					Text(verbatim: FileTransferStrings.all).tag(FileTransferSelection.all)
					Text(verbatim: FileTransferStrings.sending).tag(FileTransferSelection.sending)
					Text(verbatim: FileTransferStrings.receiving).tag(FileTransferSelection.receiving)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.frame(width: 260)
				.accessibilityLabel(FileTransferStrings.filterTransfers)

				Spacer()
				Text(verbatim: FileTransferStrings.transferCount(model.visibleTransfers.count))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)

			List(selection: $model.selection) {
				ForEach(model.visibleTransfers, id: \.uniqueIdentifier) { transfer in
					FileTransferRowView(transfer: transfer)
						.tag(transfer.uniqueIdentifier)
						.contextMenu {
							transferMenu(for: model.contextSelection(for: transfer.uniqueIdentifier))
						}
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
			.onKeyPress(.space) {
				guard model.canPerform(.preview) else { return .ignored }
				perform(.preview, model.selection)
				return .handled
			}
			.accessibilityLabel(FileTransferStrings.fileTransfers)

			Divider()
			HStack(spacing: 8) {
				Button(FileTransferStrings.clearStopped, action: clearStopped)
					.disabled(model.canClearStoppedTransfers == false)

				Spacer()

				Button {
					perform(.start, model.selection)
				} label: {
					Label(FileTransferStrings.startTransfer, systemImage: "play.fill")
				}
				.disabled(model.canPerform(.start) == false)

				Button {
					perform(.stop, model.selection)
				} label: {
					Label(FileTransferStrings.cancelTransfer, systemImage: "stop.fill")
				}
				.disabled(model.canPerform(.stop) == false)

				Button {
					perform(.preview, model.selection)
				} label: {
					Label(FileTransferStrings.quickLook, systemImage: "eye")
				}
				.disabled(model.canPerform(.preview) == false)
			}
			.controlSize(.small)
			.padding(10)
		}
		.onExitCommand(perform: close)
		.quickLookPreview($model.previewSelection, in: model.previewItems)
		.onDisappear {
			model.previewSelection = nil
			model.releaseShareAccess()
		}
		.fileImporter(
			isPresented: $model.isChoosingDestination,
			allowedContentTypes: [.folder],
			onCompletion: chooseDestination
		)
	}

	@ViewBuilder
	private func transferMenu(for identifiers: Set<String>) -> some View {
		Button(FileTransferStrings.startTransfer) { perform(.start, identifiers) }
			.disabled(model.canPerform(.start, on: identifiers) == false)
		Button(FileTransferStrings.cancelTransfer) { perform(.stop, identifiers) }
			.disabled(model.canPerform(.stop, on: identifiers) == false)

		Divider()
		Button(FileTransferStrings.quickLook) { perform(.preview, identifiers) }
			.disabled(model.canPerform(.preview, on: identifiers) == false)
		Button(FileTransferStrings.openFile) { perform(.open, identifiers) }
			.disabled(model.canPerform(.open, on: identifiers) == false)
		Button(FileTransferStrings.showInFinder) { perform(.reveal, identifiers) }
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
			perform(.remove, identifiers)
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
