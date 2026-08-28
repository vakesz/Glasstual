/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Observation

@MainActor
@Observable
final class ProgressIndicatorModel {
	enum Phase: Equatable, Sendable {
		case idle
		case running
	}

	private(set) var phase = Phase.idle

	var isRunning: Bool {
		phase == .running
	}

	func start() {
		phase = .running
	}

	func stop() {
		phase = .idle
	}
}
