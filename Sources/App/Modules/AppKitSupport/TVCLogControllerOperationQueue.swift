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

import Foundation
import os

private let logControllerOperationQueueLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogControllerOperationQueue"
)

private enum LogControllerPrintingOperationQueueKVOContext {
	nonisolated(unsafe) static var token = 0
}

private func pendingOperationsKey(for viewController: LogController) -> String {
	viewController.uniqueIdentifier
}

@objc(TVCLogControllerPrintingOperation)
private final class LogControllerPrintingOperation: Operation, @unchecked Sendable {
	@objc var executionBlock: TVCLogControllerPrintingBlock?
	@objc weak var viewController: LogController?
	@objc var pendingOperationsKey = ""
	@objc var standalone = false
	@objc var requiresExplicitFinish = false
	private let stateLock = NSLock()
	private var operationExecuting = false
	private var operationFinished = false

	@objc var isPending: Bool {
		isCancelled == false && isExecuting == false && isFinished == false
	}

	override var isAsynchronous: Bool {
		requiresExplicitFinish
	}

	override var isExecuting: Bool {
		requiresExplicitFinish ? operationExecuting : super.isExecuting
	}

	override var isFinished: Bool {
		requiresExplicitFinish ? operationFinished : super.isFinished
	}

	override func start() {
		guard requiresExplicitFinish else {
			super.start()
			return
		}

		if isCancelled {
			willChangeValue(forKey: "isFinished")
			operationFinished = true
			didChangeValue(forKey: "isFinished")
			return
		}

		willChangeValue(forKey: "isExecuting")
		operationExecuting = true
		didChangeValue(forKey: "isExecuting")

		executeBlock()

		if viewController == nil {
			finish()
		}
	}

	override func main() {
		executeBlock()
	}

	override func cancel() {
		super.cancel()

		if requiresExplicitFinish {
			finish()
		}
	}

	@objc func finish() {
		stateLock.lock()
		guard requiresExplicitFinish, operationFinished == false else {
			stateLock.unlock()
			return
		}

		willChangeValue(forKey: "isExecuting")
		willChangeValue(forKey: "isFinished")
		operationExecuting = false
		operationFinished = true
		didChangeValue(forKey: "isFinished")
		didChangeValue(forKey: "isExecuting")
		stateLock.unlock()
	}

	private func executeBlock() {
		if isCancelled || viewController == nil {
			return
		}

		executionBlock?(self)
	}

	override var isReady: Bool {
		if dependencies.count < 1 || standalone {
			let viewController = viewController
			return super.isReady && (viewController == nil || viewController!.viewIsLoaded)
		}

		return super.isReady
	}
}

@objc(TVCLogControllerPrintingOperationQueue)
public final class LogControllerPrintingOperationQueue: OperationQueue, @unchecked Sendable {
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

	@objc(enqueueMessageBlock:for:)
	public func enqueueMessageBlock(
		_ callbackBlock: @escaping TVCLogControllerPrintingBlock,
		for viewController: LogController
	) {
		enqueueMessageBlock(callbackBlock, for: viewController, isStandalone: false)
	}

	@objc(enqueueMessageBlock:for:isStandalone:)
	public func enqueueMessageBlock(
		_ callbackBlock: @escaping TVCLogControllerPrintingBlock,
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

	@objc(enqueueAsynchronousMessageBlock:for:isStandalone:)
	public func enqueueAsynchronousMessageBlock(
		_ callbackBlock: @escaping TVCLogControllerPrintingBlock,
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

	private func enqueueMessageBlock(
		_ callbackBlock: @escaping TVCLogControllerPrintingBlock,
		for viewController: LogController,
		isStandalone: Bool,
		requiresExplicitFinish: Bool
	) {
		let masterController = NSObject.masterController()
		let applicationIsTerminating: Bool

		if Thread.isMainThread {
			applicationIsTerminating = MainActor.assumeIsolated {
				masterController.applicationIsTerminating
			}
		} else {
			nonisolated(unsafe) var terminating = false
			XRPerformBlockSynchronouslyOnMainQueue {
				terminating = MainActor.assumeIsolated {
					masterController.applicationIsTerminating
				}
			}
			applicationIsTerminating = terminating
		}

		guard applicationIsTerminating == false else {
			return
		}

		let operation = LogControllerPrintingOperation()
		operation.executionBlock = callbackBlock
		operation.standalone = isStandalone
		operation.requiresExplicitFinish = requiresExplicitFinish
		operation.viewController = viewController
		operation.pendingOperationsKey = pendingOperationsKey(for: viewController)

		addPendingOperation(operation)
	}

	@objc(finishOperation:)
	public func finishOperation(_ operation: Operation) {
		(operation as? LogControllerPrintingOperation)?.finish()
	}

	@objc(pendingOperationsForViewController:)
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

		operation.addObserver(
			self,
			forKeyPath: "isFinished",
			options: .new,
			context: &LogControllerPrintingOperationQueueKVOContext.token
		)

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

		operation.removeObserver(
			self,
			forKeyPath: "isFinished",
			context: &LogControllerPrintingOperationQueueKVOContext.token
		)
	}

	@objc(cancelOperationsForViewController:)
	public func cancelOperations(for viewController: LogController) {
		for operation in pendingOperations(for: viewController) {
			operation.cancel()
		}
	}

	@objc(cancelOperationsForClient:)
	public func cancelOperations(for client: IRCClient) {
		guard let viewController = client.viewController as AnyObject as? LogController else {
			return
		}
		cancelOperations(for: viewController)
	}

	@objc(cancelOperationsForChannel:)
	public func cancelOperations(for channel: IRCChannel) {
		cancelOperations(for: channel.viewController)
	}

	@objc(updateReadinessState:)
	public func updateReadinessState(for viewController: LogController) {
		for operation in pendingOperations(for: viewController) {
			if operation.isPending == false || operation.dependencies.count > 0 {
				continue
			}

			operation.willChangeValue(forKey: "isReady")
			operation.didChangeValue(forKey: "isReady")
		}
	}

	override public func observeValue(
		forKeyPath keyPath: String?,
		of object: Any?,
		change: [NSKeyValueChangeKey: Any]?,
		context: UnsafeMutableRawPointer?
	) {
		guard context == &LogControllerPrintingOperationQueueKVOContext.token else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}

		if keyPath == "isFinished", let operation = object as? LogControllerPrintingOperation {
			removePendingOperation(operation)
		}
	}
}
