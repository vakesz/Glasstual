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
		VStack(spacing: 0) {
			HStack {
				Picker(.FileTransfer.show, selection: $model.filter) {
					Text(.FileTransfer.all).tag(FileTransferDirectionFilter.all)
					Text(.FileTransfer.sending).tag(FileTransferDirectionFilter.sending)
					Text(.FileTransfer.receiving).tag(FileTransferDirectionFilter.receiving)
				}
				.pickerStyle(.segmented)
				.fixedSize()

				Spacer()
				Text(.FileTransfer.transfers(model.visibleTransfers.count))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			.padding(.horizontal, UISpacing.wide)
			.padding(.vertical, 10)

			List(selection: $model.selection) {
				ForEach(model.visibleTransfers, id: \.uniqueIdentifier) { transfer in
					row(for: transfer)
				}
			}
			.listStyle(.inset)
			.alternatingRowBackgrounds()
			.overlay {
				if model.visibleTransfers.isEmpty {
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
			.accessibilityLabel(Text(.FileTransfer.fileTransfers))

			Divider()
			HStack(spacing: UISpacing.regular) {
				Button(.FileTransfer.clearAllStoppedTransfers, action: center.clearStoppedTransfers)
					.disabled(model.canClearStoppedTransfers == false)

				Spacer()

				Button {
					center.perform(.start, on: model.selection)
				} label: {
					Label(model.startActionTitle(), systemImage: "play.fill")
				}
				.disabled(model.canPerform(.start) == false)

				Button {
					center.perform(.downloadTo, on: model.selection)
				} label: {
					Label(.FileTransfer.downloadTo, systemImage: "folder.badge.arrow.down")
				}
				.disabled(model.canPerform(.downloadTo) == false)

				Button {
					center.perform(.stop, on: model.selection)
				} label: {
					Label(.FileTransfer.cancelTransfer, systemImage: "stop.fill")
				}
				.disabled(model.canPerform(.stop) == false)

				Button {
					center.perform(.preview, on: model.selection)
				} label: {
					Label(.FileTransfer.quickLook, systemImage: "eye")
				}
				.disabled(model.canPerform(.preview) == false)
			}
			.controlSize(.small)
			.padding(10)
		}
		.task { model.filter = storedDirectionFilter }
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
		Button(.FileTransfer.downloadTo) { center.perform(.downloadTo, on: identifiers) }
			.disabled(model.canPerform(.downloadTo, on: identifiers) == false)
		Button(.FileTransfer.cancelTransfer) { center.perform(.stop, on: identifiers) }
			.disabled(model.canPerform(.stop, on: identifiers) == false)

		Divider()
		Button(.FileTransfer.quickLook) { center.perform(.preview, on: identifiers) }
			.disabled(model.canPerform(.preview, on: identifiers) == false)
		Button(.FileTransfer.openFile) { center.perform(.open, on: identifiers) }
			.disabled(model.canPerform(.open, on: identifiers) == false)
		Button(.FileTransfer.showInFinder) { center.perform(.reveal, on: identifiers) }
			.disabled(model.canPerform(.reveal, on: identifiers) == false)

		/* Asking the model settles the rows' local files once for the whole
		 menu, and leaves the share holding the access it needs to read them. */
		let urls = model.shareableFileURLs(for: identifiers)
		ShareLink(items: urls) {
			Text(.FileTransfer.share)
		}
		.disabled(urls.count != identifiers.count)

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
				.accessibilityLabel(Text(.FileTransfer.transferProgress))
		case let .determinate(value, total):
			ProgressView(value: Double(value), total: Double(max(total, 1)))
				.progressViewStyle(.linear)
				.accessibilityLabel(Text(.FileTransfer.transferProgress))
		}
	}

	private var fileIcon: NSImage {
		let contentType = UTType(filenameExtension: (transfer.filename as NSString).pathExtension)
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
