/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

@MainActor
struct ProgressIndicatorView: View {
	let model: ProgressIndicatorModel
	let content: ProgressIndicatorContent

	var body: some View {
		HStack(spacing: 20) {
			ZStack {
				if model.isRunning {
					ProgressView()
						.progressViewStyle(.circular)
						.controlSize(.large)
						.accessibilityLabel(Text(verbatim: content.statusMessage))
				}
			}
			.frame(width: 32, height: 32)

			Text(verbatim: content.statusMessage)
				.font(.body)
				.frame(maxWidth: .infinity, alignment: .leading)
				.textSelection(.enabled)
				.accessibilityHidden(true)
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 14)
		.frame(width: 406, height: 60)
	}
}
