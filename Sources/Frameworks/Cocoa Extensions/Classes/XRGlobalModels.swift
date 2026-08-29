/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/* Everything in the tree that can reach the main actor directly now does, or
 hops with `Task { @MainActor in }`. What is left below is a shim for callers
 in other people's files; nothing new should call either function. */

private func performSynchronously(
	on queue: DispatchQueue,
	_ block: @convention(block) () -> Void
) {
	queue.sync {
		autoreleasepool(invoking: block)
	}
}

private func performAsynchronously(
	on queue: DispatchQueue,
	_ block: @escaping @convention(block) () -> Void
) {
	let workItem = DispatchWorkItem {
		autoreleasepool(invoking: block)
	}
	queue.async(execute: workItem)
}

/// Runs `block` on the main queue and waits for it to finish.
///
/// SHIM. Four callers remain, all in ChannelView's XPC clients
/// (`LogControllerHistoricLogFile`, `LogControllerInlineMediaService`), which
/// need a main-queue result to have landed before an XPC reply returns. Phase
/// 8c turns those into actors and this goes with them.
///
/// The `Thread.isMainThread` test is the last isolation exception in Cocoa
/// Extensions: without it, a caller already on the main queue would deadlock in
/// the `sync` below.
public func performSynchronouslyOnMainQueue(_ block: @convention(block) () -> Void) {
	if Thread.isMainThread {
		autoreleasepool(invoking: block)
	} else {
		performSynchronously(on: .main, block)
	}
}

/// Runs `block` on the main queue without waiting for it.
///
/// SHIM. Three callers remain, in `ApplicationController` and
/// `LogControllerHistoricLogFile`; both belong to other phases. New code hops
/// with `Task { @MainActor in }` instead.
public func performAsynchronouslyOnMainQueue(_ block: @escaping @convention(block) () -> Void) {
	performAsynchronously(on: .main, block)
}
