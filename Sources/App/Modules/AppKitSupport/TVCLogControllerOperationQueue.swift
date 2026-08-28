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

import CocoaExtensions
import Foundation
import os

private nonisolated let logControllerOperationQueueLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogControllerOperationQueue"
)

private func pendingOperationsKey(for viewController: LogController) -> String {
	viewController.uniqueIdentifier
}

public typealias LogControllerPrintingBlock = (LogControllerPrintingOperation) -> Void

/** Every mutable bit of the operation's KVO-backed state lives in this struct so
 that one lock covers all of it. KVO notifications are always posted outside the
 lock: the completion observer re-enters the queue's own bookkeeping, which takes
 a different lock, and posting under `stateLock` would invert the two. */
private struct LogControllerPrintingOperationState {
	var executing = false
	var finished = false
	/** Claimed by whichever caller of `finish()` wins the race so that only one
	 of them posts the KVO notifications. */
	var finishing = false
	/** Snapshot of the view controller's `viewIsLoaded`. `isReady` is consulted
	 by the queue on any thread and so must not read main-actor state. */
	var viewIsLoaded = false
}

/* ISOLATION-EXCEPTION: `Operation` runs on whichever thread the queue picks, so
 this cannot be isolated. Its mutable state lives behind `stateLock`, and its KVO
 posts happen outside that lock. */
@objc(TVCLogControllerPrintingOperation)
public final nonisolated class LogControllerPrintingOperation: Operation, @unchecked Sendable {
	var executionBlock: LogControllerPrintingBlock?
	weak var viewController: LogController?
	var pendingOperationsKey = ""
	var standalone = false
	var requiresExplicitFinish = false
	var finishedObservation: NSKeyValueObservation?
	private let stateLock = NSLock()
	private var state = LogControllerPrintingOperationState()

	private func withState<Result>(_ body: (inout LogControllerPrintingOperationState) -> Result) -> Result {
		stateLock.lock()
		defer { stateLock.unlock() }
		return body(&state)
	}

	var isPending: Bool {
		isCancelled == false && isExecuting == false && isFinished == false
	}

	/// Whether the view controller this operation prints into has finished
	/// loading its web view. Cached because `isReady` is read off the main actor.
	var viewIsLoaded: Bool {
		get { withState { $0.viewIsLoaded } }
		set { withState { $0.viewIsLoaded = newValue } }
	}

	override public var isAsynchronous: Bool {
		requiresExplicitFinish
	}

	@objc override public dynamic var isExecuting: Bool {
		requiresExplicitFinish ? withState { $0.executing } : super.isExecuting
	}

	@objc override public dynamic var isFinished: Bool {
		requiresExplicitFinish ? withState { $0.finished } : super.isFinished
	}

	override public func start() {
		guard requiresExplicitFinish else {
			super.start()
			return
		}

		if isCancelled {
			finish()
			return
		}

		let claimed = withState { state -> Bool in
			guard state.executing == false, state.finished == false else {
				return false
			}
			return true
		}

		guard claimed else {
			return
		}

		willChangeValue(forKey: "isExecuting")
		withState { $0.executing = true }
		didChangeValue(forKey: "isExecuting")

		executeBlock()

		if viewController == nil {
			finish()
		}
	}

	override public func main() {
		executeBlock()
	}

	override public func cancel() {
		super.cancel()

		if requiresExplicitFinish {
			finish()
		}
	}

	/// Marks an asynchronous operation complete. Safe to call from any thread
	/// and safe to call more than once; only the first call posts KVO.
	public func finish() {
		guard requiresExplicitFinish else {
			return
		}

		let claimed = withState { state -> Bool in
			guard state.finished == false, state.finishing == false else {
				return false
			}
			state.finishing = true
			return true
		}

		guard claimed else {
			return
		}

		willChangeValue(forKey: "isExecuting")
		willChangeValue(forKey: "isFinished")
		withState { state in
			state.executing = false
			state.finished = true
		}
		didChangeValue(forKey: "isFinished")
		didChangeValue(forKey: "isExecuting")
	}

	private func executeBlock() {
		if isCancelled || viewController == nil {
			return
		}

		executionBlock?(self)
	}

	func observeCompletion(_ handler: @escaping @Sendable (LogControllerPrintingOperation) -> Void) {
		finishedObservation = observe(\.isFinished, options: .new) { [weak self] _, change in
			guard change.newValue == true, let self else {
				return
			}
			handler(self)
		}
	}

	override public var isReady: Bool {
		Self.isReady(
			dependenciesAreReady: super.isReady,
			hasDependencies: dependencies.isEmpty == false,
			standalone: standalone,
			hasViewController: viewController != nil,
			viewIsLoaded: viewIsLoaded
		)
	}

	/// The readiness rule, factored out of `isReady` so it can be exercised
	/// without a live view controller. An operation that heads its own chain
	/// waits for the view it prints into; one that has a dependency inherits its
	/// readiness from that dependency instead. A view controller that has gone
	/// away can never report itself loaded, so let the operation run and drop
	/// out in `executeBlock()`.
	static func isReady(
		dependenciesAreReady: Bool,
		hasDependencies: Bool,
		standalone: Bool,
		hasViewController: Bool,
		viewIsLoaded: Bool
	) -> Bool {
		guard hasDependencies, standalone == false else {
			return dependenciesAreReady && (hasViewController == false || viewIsLoaded)
		}

		return dependenciesAreReady
	}
}

/* ISOLATION-EXCEPTION: an `OperationQueue` subclass is reached from the threads
 running its operations. Its bookkeeping is behind `pendingOperationsLock`. */
@objc(TVCLogControllerPrintingOperationQueue)
public final nonisolated class LogControllerPrintingOperationQueue: OperationQueue, @unchecked Sendable {
	/* objc_sync was recursive. Keep that behavior while using a stable lock
	 identity because operation completion can re-enter queue bookkeeping. */
	private let pendingOperationsLock = NSRecursiveLock()
	private var pendingOperations: [String: NSMutableArray] = [:]

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount
		name = "TVCLogControllerPrintingOperationQueue"
		qualityOfService = .default
	}

	@MainActor
	public func enqueueMessageBlock(
		_ callbackBlock: @escaping LogControllerPrintingBlock,
		for viewController: LogController
	) {
		enqueueMessageBlock(callbackBlock, for: viewController, isStandalone: false)
	}

	@MainActor
	public func enqueueMessageBlock(
		_ callbackBlock: @escaping LogControllerPrintingBlock,
		for viewController: LogController,
		isStandalone: Bool
	) {
		enqueueMessageBlock(
			callbackBlock,
			for: viewController,
			isStandalone: isStandalone,
			requiresExplicitFinish: false
		)
	}

	@MainActor
	public func enqueueAsynchronousMessageBlock(
		_ callbackBlock: @escaping LogControllerPrintingBlock,
		for viewController: LogController,
		isStandalone: Bool
	) {
		enqueueMessageBlock(
			callbackBlock,
			for: viewController,
			isStandalone: isStandalone,
			requiresExplicitFinish: true
		)
	}

	/** Enqueueing is main-actor work: the termination flag and the view
	 controller's load state are both main-actor state, and reading them here
	 replaces the synchronous main-queue hop this used to make per message. */
	@MainActor
	private func enqueueMessageBlock(
		_ callbackBlock: @escaping LogControllerPrintingBlock,
		for viewController: LogController,
		isStandalone: Bool,
		requiresExplicitFinish: Bool
	) {
		guard AppController.shared.applicationIsTerminating == false else {
			return
		}

		let operation = LogControllerPrintingOperation()
		operation.executionBlock = callbackBlock
		operation.standalone = isStandalone
		operation.requiresExplicitFinish = requiresExplicitFinish
		operation.viewController = viewController
		operation.viewIsLoaded = viewController.viewIsLoaded
		operation.pendingOperationsKey = pendingOperationsKey(for: viewController)

		addPendingOperation(operation)
	}

	@MainActor
	private func pendingOperations(for viewController: LogController) -> [LogControllerPrintingOperation] {
		let key = pendingOperationsKey(for: viewController)

		pendingOperationsLock.lock()
		defer { pendingOperationsLock.unlock() }

		return pendingOperations[key] as? [LogControllerPrintingOperation] ?? []
	}

	private func addPendingOperation(_ operation: LogControllerPrintingOperation) {
		var operationDependency: LogControllerPrintingOperation?
		let pendingOperationsKey = operation.pendingOperationsKey

		pendingOperationsLock.lock()

		let pendingList: NSMutableArray
		if let existing = pendingOperations[pendingOperationsKey] {
			pendingList = existing

			for case let pendingOperation as LogControllerPrintingOperation in pendingList.reversed() {
				if pendingOperation.isCancelled || pendingOperation.standalone {
					continue
				}

				operationDependency = pendingOperation
				break
			}
		} else {
			pendingList = NSMutableArray()
			pendingOperations[pendingOperationsKey] = pendingList
		}

		pendingList.add(operation)
		pendingOperationsLock.unlock()

		if let operationDependency {
			operation.addDependency(operationDependency)
		}

		operation.observeCompletion { [weak self] completedOperation in
			self?.removePendingOperation(completedOperation)
		}

		addOperation(operation)
	}

	private func removePendingOperation(_ operation: LogControllerPrintingOperation) {
		let pendingOperationsKey = operation.pendingOperationsKey

		pendingOperationsLock.lock()

		guard let pendingList = pendingOperations[pendingOperationsKey] else {
			pendingOperationsLock.unlock()
			logControllerOperationQueueLogger.error(
				"'pendingOperations' is nil when it's not supposed to be. wat?"
			)
			return
		}

		if let index = (0 ..< pendingList.count)
			.first(where: { pendingList.object(at: $0) as AnyObject === operation })
		{
			pendingList.removeObject(at: index)
		}

		if pendingList.count == 0 {
			pendingOperations.removeValue(forKey: pendingOperationsKey)
		}

		pendingOperationsLock.unlock()

		if let operationDependency = operation.dependencies.first {
			operation.removeDependency(operationDependency)
		}

		operation.finishedObservation?.invalidate()
		operation.finishedObservation = nil
	}

	@MainActor
	public func cancelOperations(for viewController: LogController) {
		for operation in pendingOperations(for: viewController) {
			operation.cancel()
		}
	}

	@MainActor
	public func cancelOperations(for client: IRCClient) {
		guard let viewController = client.viewController else {
			return
		}
		cancelOperations(for: viewController)
	}

	@MainActor
	public func cancelOperations(for channel: IRCChannel) {
		cancelOperations(for: channel.viewController)
	}

	/// Republishes the readiness of every operation waiting on `viewController`
	/// after its web view finished loading.
	@MainActor
	public func updateReadinessState(for viewController: LogController) {
		let viewIsLoaded = viewController.viewIsLoaded

		for operation in pendingOperations(for: viewController) {
			operation.viewIsLoaded = viewIsLoaded

			if operation.isPending == false || operation.dependencies.count > 0 {
				continue
			}

			operation.willChangeValue(forKey: "isReady")
			operation.didChangeValue(forKey: "isReady")
		}
	}
}
