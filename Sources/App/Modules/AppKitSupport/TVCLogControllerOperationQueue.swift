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

private func pendingOperationsKey(for viewController: TVCLogController) -> String {
	viewController.uniqueIdentifier
}

@objc(TVCLogControllerPrintingOperation)
private final class LogControllerPrintingOperation: Operation {
	@objc var executionBlock: TVCLogControllerPrintingBlock?
	@objc weak var viewController: TVCLogController?
	@objc var pendingOperationsKey = ""
	@objc var standalone = false

	@objc var isPending: Bool {
		isCancelled == false && isExecuting == false && isFinished == false
	}

	override func main() {
		executeBlock()
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
public final class LogControllerPrintingOperationQueue: OperationQueue {
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
		for viewController: TVCLogController
	) {
		enqueueMessageBlock(callbackBlock, for: viewController, isStandalone: false)
	}

	@objc(enqueueMessageBlock:for:isStandalone:)
	public func enqueueMessageBlock(
		_ callbackBlock: @escaping TVCLogControllerPrintingBlock,
		for viewController: TVCLogController,
		isStandalone: Bool
	) {
		if NSObject.masterController().applicationIsTerminating {
			return
		}

		let operation = LogControllerPrintingOperation()
		operation.executionBlock = callbackBlock
		operation.standalone = isStandalone
		operation.viewController = viewController
		operation.pendingOperationsKey = pendingOperationsKey(for: viewController)

		addPendingOperation(operation)
	}

	@objc(pendingOperationsForViewController:)
	private func pendingOperations(for viewController: TVCLogController) -> [LogControllerPrintingOperation] {
		let key = pendingOperationsKey(for: viewController)

		objc_sync_enter(pendingOperations)
		let operations = pendingOperations[key] as? [LogControllerPrintingOperation] ?? []
		objc_sync_exit(pendingOperations)

		return operations
	}

	private func addPendingOperation(_ operation: LogControllerPrintingOperation) {
		var operationDependency: LogControllerPrintingOperation?
		let pendingOperationsKey = operation.pendingOperationsKey

		objc_sync_enter(pendingOperations)

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
		objc_sync_exit(pendingOperations)

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

		objc_sync_enter(pendingOperations)

		guard let pendingList = pendingOperations[pendingOperationsKey] else {
			objc_sync_exit(pendingOperations)
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

		objc_sync_exit(pendingOperations)

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
	public func cancelOperations(for viewController: TVCLogController) {
		for operation in pendingOperations(for: viewController) {
			operation.cancel()
		}
	}

	@objc(cancelOperationsForClient:)
	public func cancelOperations(for client: IRCClient) {
		cancelOperations(for: client.viewController)
	}

	@objc(cancelOperationsForChannel:)
	public func cancelOperations(for channel: IRCChannel) {
		cancelOperations(for: channel.viewController)
	}

	@objc(updateReadinessState:)
	public func updateReadinessState(for viewController: TVCLogController) {
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
