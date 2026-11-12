import Foundation

/// As ``DCCSuccessScenario``, but the sender stops part-way and the reader
/// cancels the transfer: the partial bytes are kept, acknowledged and exact.
struct DCCCancelScenario: Scenario {
	let name = "dccCancel"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.receiveDCC(cancelling: true)
	}
}
