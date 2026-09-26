// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing
import UserNotifications

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingAuthorizationTests {
	private func model(authorization: OnboardingNotificationAuthorization) -> OnboardingModel {
		let settings = OnboardingSettings()
		settings.notifications.notifyAboutMentions = true
		let model = OnboardingModel(
			settings: settings, notificationAuthorization: authorization,
			createConnection: { _, _ in true }, applySettings: { _ in }, markCompleted: {}
		)
		model.currentStep = .notifications
		return model
	}

	@Test("Revisiting notifications shares the pending authorization request")
	func onePendingRequest() async {
		var requests = 0
		let model = model(authorization: OnboardingNotificationAuthorization(
			currentStatus: { .authorized }, request: { requests += 1; return true }
		))
		_ = model.advance()
		model.moveBack()
		_ = model.advance()
		await model.completePendingWork()
		#expect(requests == 1)
	}

	@Test("Dismissing onboarding cancels permission work before it begins")
	func dismissBeforeRequestStarts() async {
		var requests = 0
		let model = model(authorization: OnboardingNotificationAuthorization(
			currentStatus: { .authorized }, request: { requests += 1; return true }
		))
		_ = model.advance()
		let pending = Task.immediate { await model.completePendingWork() }
		model.setUpLater()
		await pending.value
		#expect(requests == 0)
	}

	@Test("Cancelled or dismissed permission reads do not publish late results", arguments: [false, true])
	func lateStatusIsIgnored(dismiss: Bool) async {
		let (started, signal) = AsyncStream<Void>.makeStream()
		var completion: CheckedContinuation<UNAuthorizationStatus, Never>?
		let model = model(authorization: OnboardingNotificationAuthorization(currentStatus: {
			await withCheckedContinuation {
				completion = $0
				signal.yield()
			}
		}, request: { true }))
		let original = model.notificationPermissionMessage
		let read = Task { await model.refreshNotificationPermission() }
		var events = started.makeAsyncIterator()
		_ = await events.next()
		if dismiss {
			model.setUpLater()
		} else {
			read.cancel()
		}
		completion?.resume(returning: .authorized)
		completion = nil
		await read.value
		#expect(model.notificationPermissionMessage == original)
		signal.finish()
	}

	@Test("A pending system prompt does not retain a dismissed onboarding model")
	func pendingRequestDoesNotRetainModel() async {
		let (started, startSignal) = AsyncStream<Void>.makeStream()
		let (returned, returnSignal) = AsyncStream<Bool>.makeStream()
		var completion: CheckedContinuation<Bool, Never>?
		var model: OnboardingModel? = model(authorization: OnboardingNotificationAuthorization(
			currentStatus: { .authorized }, request: {
				let result = await withCheckedContinuation {
					completion = $0
					startSignal.yield()
				}
				returnSignal.yield(Task.isCancelled)
				return result
			}
		))
		weak let releasedModel = model
		_ = model?.advance()
		var starts = started.makeAsyncIterator()
		_ = await starts.next()
		model = nil
		#expect(releasedModel == nil)
		completion?.resume(returning: true)
		completion = nil
		var returns = returned.makeAsyncIterator()
		#expect(await returns.next() == true)
		startSignal.finish()
		returnSignal.finish()
	}
}
